---
title: "The New Calculus of AI-based Coding"
description: "An exploration of how AI-assisted development can achieve 10x productivity gains, and why succeeding at this scale requires fundamental changes to testing, deployment, and team coordination practices."
author: "Joe Magerramov"
---

# The New Calculus of AI-based Coding

Over the past three months, a team of experienced, like-minded engineers and I have been building something really cool within Amazon Bedrock. While I'm pretty excited about what we are building, there is another unique thing about our team - most of our code is written by AI agents such as Amazon Q or Kiro. Before you roll your eyes: no, we're not vibe coding. I don't believe that's the right way to build robust software.

Instead, we use an approach where a human and AI agent collaborate to produce the code changes. For our team, every commit has an engineer's name attached to it, and that engineer ultimately needs to review and stand behind the code. We use steering rules to setup constraints for how the AI agent should operate within our codebase, and writing in Rust has been a great benefit. Rust compiler is famous for focusing on correctness and safety, catching many problems at compile time and providing helpful error messages that help the agent iterate. As a juxtaposition to vibe coding, I prefer the term "agentic coding." Much less exciting but in our industry boring is usually good.

For me, roughly 80% of the code I commit these days is written by the AI agent. My personal workflow: break down the task until I have clarity in my own head (often using AI to explore approaches), prompt the AI agent, review its output, iterate with it until I like the results, and occasionally take over the change set and finish it myself. I pay attention to every line of code the agent produces, and don't accept them until I am fully satisfied with the quality of what is being produced - no different than if I wrote every line myself.

I've always been an efficient coder, finding time to write code even in limited amount of time I've been able to dedicate to coding over the past few years. And the last few months have been the highest coding throughput months of my career. My team is no different—we are producing code at 10x of typical high-velocity team. That's not hyperbole - we've actually collected and analyzed the metrics.

## Driving at 200mph

Here's where it gets interesting. A typical software team, even an experienced one, doesn't get things right all the time. Even with good testing and engineering practices, bugs occasionally make it through. We've all heard the phrase "testing in production." That reality is the main reason I've always believed that focusing on testing alone is not enough, and investing in blast radius and time to recovery is just as important.

AI assisted code is no different, it may contain bugs even when thoroughly reviewed by a human, and I suspect the probabilities are not significantly different. However, when teams ship commits at 10x the rate, the overall math changes. What used to be a production impacting bug once or twice a year, can become a weekly occurrence. Even if most bugs get caught in integration or testing environments, they will still impact the shared code base, requiring investigation and slowing the rest of the team down. Once again, this is not just hyperbole—our team sees signs that these are the challenges that pop up with a step function increase in throughput.

I am increasingly convinced that in order for agentic development to increase engineering velocity by an order of magnitude, we need to decrease the probability of problematic commits by an order of magnitude too. And likely by even more than that, since at high velocities individual commits can begin interacting with each other in unexpected ways too.

In other words, driving at 200mph, you need a lot of downforce to keep the car on the track!

## The Cost-Benefit Rebalance

One of the best ways to reduce the chance of bugs is to improve testing. I'm an airplane geek, and have always admired the testing ideas used by the airplane manufacturers. From early simulations, to component testing, to wind tunnel testing, to testing to breaking point, and ultimately test flights of fully assembled aircraft. Even flight simulators play a role in improving the overall safety of the industry. Some of these ideas have been tried in the software industry, but they are far from ubiquitous.

As an example, I've always liked "wind tunnel" style tests, that test fully assembled system in a controlled environment. To achieve that, one pattern I've used is implementing high fidelity "fake" versions of external dependencies that can be run locally. If you do that, you can then write build-time tests that run locally and verify end-to-end behavior of the whole system. You can even inject unexpected behaviors and failures into fake dependencies, to test how the system handles them. Such tests are easy to write and execute because they run locally, and they are great at catching those sneaky bugs in the seams between components.

Unfortunately, faking all the external dependencies isn't always easy for a service with moderate level of complexity. And even if you do, you now have to own keeping up with the real dependencies as they evolve. For those reasons, in my experience most teams don't write such tests.

I think we are seeing early signs that agentic coding can change the calculus here. AI agents are great at spitting out large volumes of code, especially when the desired behavior is well known and there's little ambiguity. Ideas that were sound in principle, but too expensive to implement and maintain just had their costs decrease by an order of magnitude. I really love riding such shifts in the industry, because they open the doors to new approaches that weren't practical in the past.

Our project (with the help of an AI agent) maintains fake implementations of external dependencies like authentication, storage, chain replication, and inference engine to be used in tests. We then wrote a test harness that uses those fakes to spin up our entire distributed system, including all the micro-services, on developers' machines. Build-time tests then spin up our canaries against that fully assembled stack verifying the system as a whole works.

I'm really bullish on this approach catching a category of bugs that in the past could only be caught once the change was committed and made it to the test environment. A few years ago, ideas like these would receive resistance as nice, but too expensive. This time around, it took just a few days to implement for a relatively complex system.

## Driving Fast Requires Tighter Feedback Loop

At the end of the day, all these changes need to be built, tested, and deployed in order to bring customer value. It's not uncommon for software teams to have a CICD pipeline that takes several hours to build, package, and then test software changes. That pipeline can then take a few days to roll a batch of changes across pre-prod stages and eventually production stages. Typically, a team with that level of automation would be considered a healthy team.

Agentic coding changes that dynamic. In the amount of time it takes to build, package, and test one set of commits, another dozen might be waiting to go out. By the time a change set is ready to deploy to production, it may contain 100 or more commits. And if one of those commits contains a problem, the deployment needs to be rolled back grinding the pipeline to a halt. In the meantime, even more changes accumulate, adding to the chaos and the risk.

I'm a Formula 1 fan, and this reminds me of how an accident on the track can cause a Yellow Flag to be raised. Normally, the cars zoom around the track at immense speeds and accelerations. But if an accident occurs, the race marshals raise a yellow flag, which requires all the cars to slow down behind the pace car. An exciting race turns into a leisurely drive around the track until the debris is cleaned up and the track is safe again. To minimize such slow downs, race organizers go to great lengths to prepare for all types of accidents, and make sure they can clean up the track and restart the race in minutes.

Just like whole-system local tests help tighten the feedback loop for catching certain bugs, we may need to think similarly about how we implement our CICD pipelines. When teams are moving at the speed of dozen of commits per hour, problematic issues will need to be identified, isolated, and reverted in minutes instead of hours or days. That means that a typical build and test infrastructure will need to become an order of magnitude faster than it is today. Just like online video games become unplayable when there is high lag between player's inputs and the game's reaction, it's really hard to move 10x faster if every commit still requires a lengthy delay before you see the feedback.

## The Communication Bottleneck

I enjoy observing well-run operations. If you've ever peeked behind the curtain of a busy restaurant, then at first sight you may think it's chaos. But if you take a second to notice the details, you'll see that all members are constantly coordinating with each other. Chefs, cooks, wait staff, bussers, and managers pass information back and forth in a continuous stream. By staying in constant sync, a well run restaurant manages to serve its patrons even during peak times, without sacrificing on quality or latency.

I believe that achieving similar increase in velocity for a software team requires constraints on how teams communicate. When your throughput increases by an order of magnitude, you're not just writing more code - you're making more decisions. Should we use this caching strategy or that one? How should we handle this edge case? What's the right abstraction here? At normal velocity, a team might make one or two of these decisions per week. At 10x velocity, they are making multiple each day.

The challenge is that many of these decisions impact what others are working on. Engineer A decides to refactor the authentication flow, which affects the API that Engineer B is about to extend. These aren't just implementation details - they're architectural choices that ripple through the codebase.

I find that traditional coordination mechanisms introduce too much latency here. Waiting for a Slack response or scheduling a quick sync for later in the day means either creating a bottleneck - the decision blocks progress - or risking going down the wrong path before realizing the conflict. At high throughput, the cost of coordination can dominate!

One approach is to eliminate coordination - if everybody works on independent components, they are unlikely to need to coordinate. But I find that ideal impractical in most real-world systems. So another alternative is to significantly decrease the cost of coordination. Our team sits on the same floor, and I think that's been critical to our velocity. When someone needs to make a decision that might impact others, they can walk over and hash it out in minutes in front of a whiteboard. We align on the approach, discuss trade-offs in real time, and both engineers get back to work. The decision gets made quickly, correctly, and without creating a pile-up of blocked work.

I recognize this doesn't solve the problem for distributed teams—that remains an open challenge.

## The Path Forward

I'm really excited about the potential of agentic development. I think it has the capability to not only improve the efficiency of software development, but also allow us to tackle problems that were previously too niche or expensive to solve. The gains are real - our team's 10x throughput increase isn't theoretical, it's measurable.

But here's the critical part: these gains won't materialize if we simply bolt AI agents onto our existing development practices. Like adding a turbocharger to a car with narrow tires and old brakes, the result won't be faster lap times - it will be crashes. At 10x code velocity, our current approaches to testing, deployment, and team coordination become the limiting factors. The bottleneck just moves.

This means we need to fundamentally rethink how we approach building software. CICD pipelines designed for 10 commits per day will buckle under 100. Testing strategies that were "good enough" at normal velocity will let too many bugs through at high velocity. Communication patterns that worked fine before will create constant pile-ups of blocked work.

The good news is that we already have great ideas for comprehensive testing, rapid deployment, and efficient coordination - ideas that have shown promise but haven't seen wide adoption because they were too expensive to implement and maintain. What's changed is that agentic development itself can dramatically lower those costs. The same AI agents that are increasing our code throughput can also help us build the infrastructure needed to sustain that throughput.

This is the real opportunity: not just writing more code faster, but using AI to make previously impractical engineering practices practical. The teams that succeed with agentic development will be the ones who recognize that the entire software development lifecycle needs to evolve in concert.