# RubyLLM VertexAI GCE Authentication Fix

## PR Submitted

**URL:** https://github.com/crmne/ruby_llm/pull/520

**Status:** Pending review

**Date:** 2025-12-01

## The Bug

When using RubyLLM 1.9.1 with the VertexAI provider on a Google Compute Engine VM, authentication fails with:

```
TypeError: Expected Array or String, got Hash
```

### Root Cause

In `lib/ruby_llm/providers/vertexai.rb`, the `initialize_authorizer` method passes `scope:` as a keyword argument:

```ruby
# BROKEN - scope: is interpreted as a Hash
@authorizer = ::Google::Auth.get_application_default(
  scope: [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/generative-language.retriever'
  ]
)
```

But `Google::Auth.get_application_default` expects scope as a **positional argument**:

```ruby
# Method signature
def get_application_default(scope = nil, options = {})
```

Ruby interprets `scope: [...]` as passing a Hash `{scope: [...]}` to the first positional parameter, which the signet gem rejects.

### The Fix

Change from keyword to positional argument:

```ruby
# FIXED - pass Array directly as positional argument
@authorizer = ::Google::Auth.get_application_default(
  [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/generative-language.retriever'
  ]
)
```

## Our Workaround

Until the PR is merged and a new version released, we have a monkey-patch in place:

**File:** `config/initializers/ruby_llm_vertexai_patch.rb`

This patch overrides `RubyLLM::Providers::VertexAI#initialize_authorizer` with the correct positional argument syntax.

## How We Found This

1. Episode processing jobs were failing after deploying the URL-to-TTS feature
2. Kamal logs showed `TypeError: Expected Array or String, got Hash`
3. Stack trace pointed to `signet-0.21.0/lib/signet/oauth_2/client.rb:420`
4. Traced back to `ruby_llm-1.9.1/lib/ruby_llm/providers/vertexai.rb:43`
5. Discovered the keyword vs positional argument issue

### Full Stack Trace

```
/gems/signet-0.21.0/lib/signet/oauth_2/client.rb:420:in 'Signet::OAuth2::Client#scope=': Expected Array or String, got Hash (TypeError)
    from /gems/signet-0.21.0/lib/signet/oauth_2/client.rb:193:in 'Signet::OAuth2::Client#update!'
    from /gems/googleauth-1.15.1/lib/googleauth/signet.rb:55:in 'Signet::OAuth2::Client#update!'
    from /gems/googleauth-1.15.1/lib/googleauth/compute_engine.rb:168:in 'Google::Auth::GCECredentials#update!'
    from /gems/signet-0.21.0/lib/signet/oauth_2/client.rb:115:in 'Signet::OAuth2::Client#initialize'
    from /gems/googleauth-1.15.1/lib/googleauth/compute_engine.rb:94:in 'Google::Auth::GCECredentials#initialize'
    from /gems/googleauth-1.15.1/lib/googleauth/application_default.rb:61:in 'Google::Auth.get_application_default'
    from /gems/ruby_llm-1.9.1/lib/ruby_llm/providers/vertexai.rb:43:in 'RubyLLM::Providers::VertexAI#initialize_authorizer'
```

## Additional Issue Discovered

During debugging, we also discovered the GCE VM was missing the required OAuth scope. The VM needed `cloud-platform` scope to access Vertex AI APIs.

**Original VM scopes:**
- `devstorage.read_only`
- `logging.write`
- `monitoring.write`
- `service.management.readonly`
- `servicecontrol`
- `trace.append`

**Required scope:**
- `https://www.googleapis.com/auth/cloud-platform`

The VM was recreated with the proper scope (new IP: 34.106.61.4).

## Environment

- ruby_llm 1.9.1
- googleauth 1.15.1
- signet 0.21.0
- Ruby 3.4.5
- Google Compute Engine VM
- Rails 8.1.1

## Next Steps

1. **Wait for PR review** from RubyLLM maintainers
2. **If merged:** Update Gemfile to new version and remove monkey-patch
3. **If changes requested:** Address feedback and update PR

## Related Files

- `config/initializers/ruby_llm_vertexai_patch.rb` - Our temporary monkey-patch
- `config/initializers/ruby_llm.rb` - RubyLLM configuration
- `app/services/llm_client.rb` - Our LLM client wrapper

## Commits

- `4619e22` - fix: Patch RubyLLM 1.9.1 VertexAI auth bug on GCE
- `c0aec24` - chore: Update VM IP address to 34.106.61.4
