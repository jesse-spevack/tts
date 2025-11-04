# Creating email-based passwordless authentication in Rails

**Discover the step-by-step guide to implementing email-based passwordless authentication in your Rails app. Create secure and seamless user experiences with magic links!**

**Justin Searls** | October 24, 2022

---

I'm working on a new Rails app, and I finally got to the part where I need to figure out how I'm going to handle authentication.

What'll it be this time? I could:

- Depend on Devise, which is popular and feature-rich, but is so complex that—if I'm being honest—I would never understand how my own app's authentication system worked
- Outsource identity management to an OAuth service like Google, Facebook, Twitter, or GitHub, whether by using an omniauth adapter or by rolling my own
- Implement a password management system for the app using `has_secure_password` and rebuilding all the supporting features that tend to tag along (e.g. email confirmation, password reset, changing email addresses)
- Adopt the burgeoning Passkey standard using Webauthn, which relies on the cryptographic security of people's modern computing devices to act as tokens

I thought long and hard about it, but I didn't like any of these options. I look forward to being able to quickly plug in a Passkey-based authentication feature, but we're just not there yet.

Ultimately, I settled on creating an email-based passwordless authentication workflow. You've probably experienced something like this as a user:

1. Enter your email address
2. Check your inbox
3. Click the link
4. Be logged in
5. Feel annoyed it opened a new tab

(Unfortunately, it seems not much can be done about Step 5.)

Asking users to shuffle between an app and their email inbox has always felt suboptimal. That said, it's important to consider that most password-based account systems represent the same thing with extra steps by requiring users to open an email to verify their address or reset their password. So if there's any superfluity to be eliminated from a self-hosted authentication system, it's with the password, not the email address.

So, with that settled: where to start?

## Can't a gem do this for us?

Whenever implementing a feature that others have certainly done before, I'll be the first to reach for the nearest search engine and type: `{{description of feature}} ruby on rails` and see if there's a good-enough drop-in solution to the problem. And indeed, my cursory survey yielded several gems that implement this workflow. Unfortunately, none seemed to fit my (rather exacting) preferences for being minimal, opinionated, and well-encapsulated. And regardless, authentication is one area of your app that's worth understanding and owning—it's so critical that if it ever breaks, you'll want to be in total control over fixing it.

When "gem shopping" fails to yield an immediate answer, I like to sketch out my ideal gem API. The goal isn't necessarily to plan to build a new gem (though it might explain why I end up making so many of them), but rather to validate whether a sound gem API could exist at all in the context of a Rails app. The more Rails features that a gem interfaces with, the less encapsulated its API could possibly be and—even if Railties exposed every necessary extension point—the more magical and mysterious the gem's API would seem to users.

Consider all of the headline features of Rails that an email-based passwordless authentication workflow would need to touch:

- **Active Record** for persisting an authentication token and its expiration to the database
- **Action Dispatch** for setting up routing to a login form, submission action, authentication handler, and logout path
- **Action Controller** for implementing the above actions, the requisite session management, and for setting up a general `before_action` filter to ensure users are logged in (or else redirected to a login page)
- **Action View** for rendering the form and the email
- **Active Job** for deferring the delivery of emails until after the HTTP response is complete
- **Action Mailer** for sending emails

Wow, authentication features depend on a lot of Rails APIs to do their job! Almost every border between our app and the outside world is crossed at some point.

Just try to imagine a gem that could implement all of this for us while providing a straightforward API made up of simple methods and boring return values. Now think about how it might gracefully handle every permutation of application configuration: alternative templating languages, non-relational databases, non-default session stores… maintenance would be a nightmare! By these standards, a "good" library may not even be possible.

By the end of this exercise, I was confident in my conviction that rolling my own authentication code would be outright better than relying on a dependency, no matter how well-designed.

## How would we build this?

Authentication features are often better imagined as a workflow of discrete steps rather than as a spatial arrangement of components, because the process necessarily spans multiple HTTP requests, emails, and user actions.

So what might that workflow look like?

1. A controller filter detects a request isn't authenticated and redirects the user to a login form
2. The user types in their email and clicks "Sign in" or "Create Account"
3. The system sends an email with a magic link by:
   - Matching the email address to the corresponding user (or else creating a new one)
   - Generating a secure token and persisting it alongside an expiry timestamp
   - Delivering an email with a link that includes the token as a query parameter
4. The user opens the email and clicks the link
5. The authentication action looks up the user by the token and, if it's valid, assigns their ID to a session variable

As with any feature, there are numerous other complications we could choose to either implement or defer along the way. Maybe we want to pass a redirect path along with the token so the user will be directed to the page they were originally trying to access when they were prompted to sign in. Or we could mitigate a denial of service attack vector by rate-limiting the number of emails the system will send. Or we might first check that the user doesn't have an existing non-expired token before generating a new one—that way, they'd receive the same valid magic link across multiple emails.

Rather than get too in the weeds with complications, let's start building a straightforward version of this feature and take things one step at a time.

> The code snippets in this blog post have been gently edited for readability, so we've published an example app where you can see everything plugged together in [testdouble/magic_email_demo on GitHub](https://github.com/testdouble/magic_email_demo).

## Ensuring users are logged in with a before_action filter

Our very first step will be to require users to be signed in by adding a controller filter that checks the session (by default encrypted by CookieStore) for a previously-authenticated user ID.

```ruby
class ApplicationController < ActionController::Base
  before_action :require_login

  def require_login
    @current_user = User.find_by(id: session[:user_id])
    return if @current_user.present?

    redirect_to new_login_email_path(
      redirect_path: request.original_fullpath
    )
  end
end
```

Reading the method, you might notice the `require_login` filter performs two unrelated tasks. First, it sets a `@current_user` instance variable for use by the controller action. Second, if no User was found, no one is logged in and therefore the request should be considered unauthorized, so the user is redirected to a login form. To ensure we direct the user to the page they intended to visit, we do one last sneaky thing by appending `request.original_fullpath` to a query param named `redirect_path`, which we'll ultimately append to the magic link we email the user.

> **Note:** By choosing to make authentication required by default across the application, we won't run the risk of allowing unauthenticated users to access privileged areas of the app in the event we forget to sprinkle in a `before_action` at the top.

Because the above filter will run for every single controller action in our application, the user's browser would be repeatedly redirected to the same `new_login_email_path` unless that path's corresponding controller action skipped the `require_login` filter. So while we're here, let's add a convenience method to allow controllers to opt out of the authentication requirement:

```ruby
def self.logged_out_users_welcome!
  skip_before_action :require_login
end
```

## Creating a login form without a password field

Designing a great login form is notoriously difficult, but passwordless email-based authentication will let us eliminate one field, at least.

To start, that `new_login_email_path` method isn't defined yet. We can demand it into existence in `config/routes.rb` with:

```ruby
Rails.application.routes.draw do
  resource :login_email
  # …
end
```

And create a corresponding controller in `login_emails_controller.rb` with a `new` action that grabs the `redirect_path` parameter:

```ruby
class LoginEmailsController < ApplicationController
  logged_out_users_welcome!

  def new
    @redirect_path = params[:redirect_path]
  end
end
```

> **Heads up:** Rails 7 defaults to raising an error when redirecting to an external domain. This prevents our `redirect_path` parameter from being manipulated by a malicious actor to mislead a user. You should make sure `config.action_controller.raise_on_open_redirects` is enabled.

From here, we can start a `new.html.erb` form in `views/login_emails`:

```erb
<%= form_with url: login_email_path do |f| %>
  <%= f.hidden_field :redirect_path, value: @redirect_path %>
  <%= f.email_field :email, placeholder: "human@example.com" %>
  <%= f.submit "Send Login Link" %>
<% end %>
```

In our (slightly more styled) sample app, that form looks something like this:

**Our simple one-field login form**

When a user enters an email address and submits the form, the `create` action of our controller will be invoked, so we'll write that next.

## Handling the form submission

Here's what the `create` action looks like in `LoginEmailsController`:

```ruby
def create
  EmailAuth::EmailsLink.new.email(
    email: params[:email],
    redirect_path: params[:redirect_path]
  )
  flash[:notice] = "E-mail sent to #{params[:email]} (probably!)"
  redirect_to login_email_path
end
```

> **Note:** The `login_email_path` just renders a simple HTML page instructing users to check their email.

Granted, the way I program in Rails is idiosyncratic, but hopefully it's clear enough:

- `EmailAuth` is a namespace under `app/lib` where we'll put as much of this feature's behavior as can be separated from Rails constructs like controllers and mailers
- `EmailsLink` is a verb-first class name, which is a practice I follow to differentiate objects implementing features from objects encapsulating data values
- The `EmailsLink#email` method does just that: emails the given address a magic link. I try to separate command and query methods when possible, which is why—as a command—the method doesn't return a meaningful value

I often talk about immediately searching for an "escape hatch" when writing Rails controller actions. Controllers agglomerate so many disparate concerns on their own that adding custom application logic to an action very often leads to mingling feature behavior with controller specifics like `session`, `params`, and `response`. Once this happens, it can be extraordinarily difficult to extract the resulting procedural code into plain ol' Ruby objects ("POROs"). By immediately delegating to `EmailsLink` before giving the feature a second thought, we can make sure to avoid that outcome.

> **Note:** While these examples are shared in order, I actually wrote this feature working outside in by practicing what I call "Discovery Testing" to test-drive a design for `EmailsLink` by imagining all of the dependencies it might need specifying those interactions using our Mocktail gem before I implemented any of the feature's actual behavior. If you're interested, check out the [EmailsLinkTest source](https://github.com/testdouble/magic_email_demo/blob/main/test/lib/email_auth/emails_link_test.rb) and work outside-in.

Now that we have our entry point defined, let's go to work and figure out how to generate magic links!

## Finding (or creating) a user for the given email address

In this simple example, we're going to let anyone create an account with any email address. If the provided address matches a User record, we'll return it; otherwise we'll create a new one. (We probably wouldn't normally design a form that made it quite so easy to accidentally persist new users in production, however.)

Let's start by making our `EmailsLink` entry point real:

```ruby
module EmailAuth
  class EmailsLink
    def email(email:, redirect_path:)
    end
  end
end
```

Because this object's role is to orchestrate several tasks needed to send or generate an email with a magic link, let's proactively push the implementation of any of those behaviors into first-class objects in their own right. Let's start with something responsible for pairing up email addresses with user models.

```ruby
module EmailAuth
  class EmailsLink
    def initialize
      @finds_or_creates_user = FindsOrCreatesUser.new
    end

    def email(email:, redirect_path:)
      user = @finds_or_creates_user.find_or_create(email)
    end
  end
end
```

The best place to think of a class or method name is inside the thing that needs to use it, because there's no place where it's more important for the names we choose to make sense. And there's no easier way to validate that a new method's parameters and return value are workable.

Since this is the only way to create users in my app, it makes sense to give it an easy-to-find name like `FindsOrCreatesUser`. Because the class name says what the object does, the method name is uselessly redundant. In some apps, I'll name each method `call` so it quacks like a Proc. In this app, I gave each method a descriptive name instead, in case I later choose to collapse multiple small classes into a larger one.

Here's `FindsOrCreatesUser`'s implementation:

```ruby
module EmailAuth
  class FindsOrCreatesUser
    def find_or_create(email)
      user = User.find_or_create_by(
        email: email.strip.downcase
      )
      if user.persisted?
        user
      end
    end
  end
end
```

Most of the heavy lifting here is done by `ActiveRecord::Relation`'s handy `find_or_create_by` method, of course. Because we are calling the bangless version of the method (as opposed to `find_or_create_by!`), it will actually return an invalid unpersisted model if an email address is malformed. We want this object to return `nil` in that case, which is why we need the `persisted?` check.

## Generating an authentication token

With that implemented, we can return to `EmailsLink` and think about our next requirement:

```ruby
module EmailAuth
  class EmailsLink
    def initialize
      @finds_or_creates_user = FindsOrCreatesUser.new
      @generates_token = GeneratesToken.new
    end

    def email(email:, redirect_path:)
      return unless (user = @finds_or_creates_user.find_or_create(email))

      token = @generates_token.generate(user)
    end
  end
end
```

> **Note:** Tastes vary on how densely-packed this is, but note that we turned our `find_or_create` assignment into a guard clause by prepending `return unless`. This will effectively bail out when an invalid email address is submitted.

Following the same pattern, we added a dependency named `GeneratesToken` that takes a user. Here's its implementation:

```ruby
module EmailAuth
  class GeneratesToken
    TOKEN_SHELF_LIFE = 30

    def generate(user)
      unless user.auth_token.present? && user.auth_token_expires_at.future?
        user.update!(
          auth_token: SecureRandom.urlsafe_base64,
          auth_token_expires_at: TOKEN_SHELF_LIFE.minutes.from_now
        )
      end
      user.auth_token
    end
  end
end
```

If a user already has an unexpired authentication token, `generate` will simply return it. Otherwise, it will save a new token and an expiration timestamp set thirty minutes in the future.

If you've never used `SecureRandom` before, it's a super convenient way to generate immediately-useful cryptographically-secure values by relying on openssl or the underlying operating system as opposed to Ruby's internal `Random` class.

## Delivering an email with a magic link

We now have what we need to send an email that can enable users to log into the system. Let's update our `EmailsLink` class to depend on a newly-imagined dependency to handle this for us:

```ruby
module EmailAuth
  class EmailsLink
    def initialize
      @finds_or_creates_user = FindsOrCreatesUser.new
      @generates_token = GeneratesToken.new
      @delivers_email = DeliversEmail.new
    end

    def email(email:, redirect_path:)
      return unless (user = @finds_or_creates_user.find_or_create(email))

      @delivers_email.deliver(
        user: user,
        token: @generates_token.generate(user),
        redirect_path: redirect_path
      )
    end
  end
end
```

Above, `DeliversEmail#deliver` takes the keyword arguments the email template will be interested in. (As a command method, any return value is incidental.) I decided to pass the token separately as opposed to expecting the mailer to know that the token is persisted as part of a User record, since that's an implementation detail that could reasonably change (in keeping with the spirit of the Law of Demeter).

If you have an allergy to very small classes, you may experience a reaction to the implementation of `DeliversEmail`, however:

```ruby
module EmailAuth
  class DeliversEmail
    def deliver(user:, token:, redirect_path:)
      LoginLinkMailer.with(
        user: user,
        token: token,
        redirect_path: redirect_path
      ).login_link.deliver_later
    end
  end
end
```

Personally, I don't mind this indirection. The Action Mailer API has always felt awkward to use. Messages are defined as instance methods but invoked as class methods. There are multiple ways to assign arguments. Calling `deliver_now` is almost always wrong, but so is expecting every developer to remember as much each time they invoke a mailer. So if a little wrapper object can provide a better experience to the method's caller, I'd take that deal.

The mailer itself mostly shovels its params to its view, since the bulk of the work has been done already in our POROs (`FindsOrCreatesUser` and `GeneratesToken`):

```ruby
class LoginLinkMailer < ApplicationMailer
  def login_link
    @user = params[:user]
    @token = params[:token]
    @redirect_path = params[:redirect_path]

    mail(
      to: @user.email,
      subject: "Your Magic Login Link"
    )
  end
end
```

Speaking of the view, `login_link.html.erb` is also simple and straightforward:

```erb
<h1>Hello!</h1>
<p>
  Here is your
  <%= link_to "link to login",
    login_emails_authenticate_url(
      token: @token,
      redirect_path: @redirect_path
    )
  %>.
  It expires in <%= EmailAuth::GeneratesToken::TOKEN_SHELF_LIFE %> minutes.
</p>
```

Importantly, when calling a `_url` helper, Rails needs to know the correct protocol, domain, and port to prefix to the path. This is exposed in Action Mailer's configuration and is often handled separately for each environment.

In `config/development.rb`, I point to `localhost:3000` since that's where the server is bound by default:

```ruby
config.action_mailer.default_url_options = {
  host: "localhost",
  port: "3000"
}
```

And in `config/test.rb`, I specify only what I need to in order to give my tests something to assert against:

```ruby
config.action_mailer.default_url_options = {
  host: "example.com"
}
```

## Opening the email and clicking the link

By default, emails will be printed to the log in development, but keeping an eye on a terminal to scan and copy-paste a carefully-coiffed URL inside an HTML email is tedious, time-consuming, and a poor approximation of a real user's experience. At the same time, setting up actually-working-for-real email delivery in development is more trouble than it's worth.

> **Note:** Normally, I use Action Mailer's built-in preview feature for inspecting emails generated by my app, but because each email contains a time-sensitive URL with a unique token that determines who gets logged in, it isn't a good fit for opening an email as a step in a workflow.

That's what led me to pull in the `letter_opener` gem for the first time. Simply add the gem to your Gemfile's `:development` group and sprinkle two more lines into your `config/development.rb`:

```ruby
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
```

As soon as `letter_opener` is wired up, any emails sent by the system will be instantly opened in a new browser tab, both saving time and displaying what the rendered HTML will look like:

**An email preview in Safari**

Because this feature is composed of so many steps, it's worth pausing at each point to validate that the parameters are being sent correctly before we move onto the next step. To verify the URL in the email, I first visited `localhost:3000/numbers?count=8`, allowed myself to be redirected, and then submitted the login form.

Here's the URL that was contained in the email's link:

```
http://localhost:3000/login_emails/authenticate?redirect_path=%2Fnumbers%3Fcount%3D8&token=EnJBIJKJczC0jI4sBMwMPg
```

Valid-looking token? Check. URL-encoded `redirect_path` seem right? Check.

## Authenticating a login request

Good news! It's time to authenticate that a user's request includes a valid token and assign them to a session. Because we've eschewed a typical login form, we won't be responding to an HTTP POST request with a corresponding `create` action. (And because email clients don't execute JavaScript, we can't trick them into sending a POST when clicking that link, either.)

Instead, let's add a custom route to our existing controller that can respond to both GET and POST requests and name both the path fragment and the action `authenticate`:

```ruby
Rails.application.routes.draw do
  match "login_emails/authenticate", to: "login_emails#authenticate", via: [:get, :post]
  resource :login_email
  # …
end
```

And here's that `authenticate` action's implementation:

```ruby
class LoginEmailsController < ApplicationController
  # …
  def authenticate
    result = EmailAuth::ValidatesLoginAttempt.new.validate(params[:token])
    if result.success?
      reset_session
      session[:user_id] = result.user.id
      flash[:notice] = "Welcome, #{result.user.email}!"
      redirect_to params[:redirect_path]
    else
      flash[:error] = "We weren't able to log you in with that link. Try again?"
      redirect_to new_login_path(redirect_path: params[:redirect_path])
    end
  end
end
```

> **Note:** If you're familiar with session management in Rails, this should be familiar. Because the response ends by redirecting to the user's originally-intended path, that request will run our `require_login` filter, which will, in turn, use `session[:user_id]` to populate a `@current_user` instance variable for each subsequent request.

There's a reason this is the application's longest method in any class that extends a Rails type: every single thing it does must be invoked from a controller: `reset_session`, `session`, `flash[]`, and `redirect_to`. There's enough going on here to make me glad for my "escape hatch" strategy of implementing feature logic someplace outside the controller itself.

With that in mind, let's take a look at `ValidatesLoginAttempt` referenced above:

```ruby
module EmailAuth
  class ValidatesLoginAttempt
    Result = Struct.new(:success?, :user, keyword_init: true)

    def validate(token)
      user = User.where(auth_token: token)
        .where("auth_token_expires_at > ?", Time.zone.now)
        .first

      if user.present?
        Result.new(success?: true, user: user)
      else
        Result.new(success?: false)
      end
    end
  end
end
```

Fortunately, the implementation isn't too complicated. While it does make the assumption that `SecureRandom.urlsafe_base64` will never return the same string twice in a fifteen minute period, that's probably a safe bet.

The only pattern worth commenting on here is the declaration of a `Result` Struct to return a value that can both indicate `success?` and identify the user to the caller. We could have just as well conditionally returned a User or `nil`, but sometimes it's nice to return a value that's explicit about a query method's outcome. Given that the thing we're writing is named "validate", the primary response a caller should expect is "yes" or "no", and any reference to the user is merely metadata associated with a successful response.

It's time for the moment of truth: clicking the link in the email we just sent and seeing if it successfully logs us in and redirects us to where we want to go:

**A successfully authenticated page**

Huzzah! We're logged in! And our original path was successfully propagated, too! (Try not to think too hard about the fact that the application we've been working so hard to protect with this authentication system apparently does nothing but generate colorful random numbers.)

## Allowing users to log out

Not a lot of people know this, but the most commonly-requested feature after implementing a login system is to provide some way for users to log out. Let's save our product owner a step and just handle that ourselves now.

In our ERB template, we can rely on the `turbo-rails` gem to make an ordinary `<a>` tag trigger an HTTP DELETE request by adding a `data-turbo-method="delete"` attribute to the link like this:

```erb
<%= link_to "Log out", login_email_path, data: { "turbo-method": :delete } %>
```

> **Heads up:** this recently changed! Prior to Rails 7, this attribute would have been named `data-method` and observed by rails-ujs as opposed to Turbo.

Now that we have a link that maps to our `LoginEmailsController`'s `destroy` action, we can easily implement it:

```ruby
class LoginEmailsController < ApplicationController
  def destroy
    reset_session
    flash[:notice] = "Your account has been successfully logged out."
    redirect_to new_login_email_path
  end
  # …
end
```

That's it! After everything we've been through together, it feels nice to write a simple three-line method as a controller action.

## Thanks for taking the time

Maybe you landed here because you're interested in adding an email-based login feature to your Rails app. In that case, I hope this tutorial helps you build your own! Showing people how to do stuff is definitely one reason I write blog posts that show people how to do stuff.

But there's another reason. Why take what could have been a dozen code examples and instead publish a 4000 word tutorial? Because I believe code alone can never tell the whole story. Code as an artifact is merely a distillation of countless hard questions, failed experiments, and iterative tweaks that programmers must endure to ship working software. Behind each variable name is an expression of intent. Behind every if statement lies a design choice. And the more input we as developers receive of different ways to approach planning, structuring, and modifying code, the better prepared we will be for the innumerable challenges we encounter in this profession.

Conference talks, screencasts, technical books, and blog posts like this one can all help us learn how to both write code and how to think about writing code. But nothing will ever beat the real deal: practicing the craft of writing code yourself. At Test Double, we've assembled a cadre of programmers who are not only excellent practitioners, but brilliant communicators, talented teachers, and empathetic teammates. If you find value in content like this, you wouldn't believe how much more there is to be gained by pair-programming with a Test Double agent to work alongside you in your team's codebase, thinking through hard problems with you in real-time, and striving to get things done at a level of quality we can all take pride in.

If that's an experience you'd be interested in having for yourself and your team, please reach out to us to talk about how Test Double might work with your company, both to build great things and to improve as software engineers.
