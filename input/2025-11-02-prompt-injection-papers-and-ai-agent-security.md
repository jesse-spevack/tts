---
title: "New Prompt Injection Papers: Agents Rule of Two and The Attacker Moves Second"
description: "Two significant research papers examine AI agent security and prompt injection defenses, while GitHub Universe showcases hackable conference badges and the AI coding tool landscape continues to evolve rapidly."
author: "Simon Willison"
---

# New Prompt Injection Papers: Agents Rule of Two and The Attacker Moves Second

Two interesting new papers regarding LLM security and prompt injection came to my attention this weekend.

## Agents Rule of Two: A Practical Approach to AI Agent Security

The first is Agents Rule of Two: A Practical Approach to AI Agent Security, published on October 31st on the Meta AI blog. It doesn't list authors but it was shared on Twitter by Meta AI security researcher Mick Ayzenberg.

It proposes a "Rule of Two" that's inspired by both my own lethal trifecta concept and the Google Chrome team's Rule Of 2 for writing code that works with untrustworthy inputs:

At a high level, the Agents Rule of Two states that until robustness research allows us to reliably detect and refuse prompt injection, agents must satisfy no more than two of the following three properties within a session to avoid the highest impact consequences of prompt injection.

An agent can process untrustworthy inputs

An agent can have access to sensitive systems or private data

An agent can change state or communicate externally

It's still possible that all three properties are necessary to carry out a request. If an agent requires all three without starting a new session (i.e., with a fresh context window), then the agent should not be permitted to operate autonomously and at a minimum requires supervision via human-in-the-loop approval or another reliable means of validation.

I like this a lot.

I've spent several years now trying to find clear ways to explain the risks of prompt injection attacks to developers who are building on top of LLMs. It's frustratingly difficult.

I've had the most success with the lethal trifecta, which boils one particular class of prompt injection attack down to a simple-enough model: if your system has access to private data, exposure to untrusted content and a way to communicate externally then it's vulnerable to private data being stolen.

The one problem with the lethal trifecta is that it only covers the risk of data exfiltration: there are plenty of other, even nastier risks that arise from prompt injection attacks against LLM-powered agents with access to tools which the lethal trifecta doesn't cover.

The Agents Rule of Two neatly solves this, through the addition of "changing state" as a property to consider. This brings other forms of tool usage into the picture: anything that can change state triggered by untrustworthy inputs is something to be very cautious about.

It's also refreshing to see another major research lab concluding that prompt injection remains an unsolved problem, and attempts to block or filter them have not proven reliable enough to depend on. The current solution is to design systems with this in mind, and the Rule of Two is a solid way to think about that.

Which brings me to the second paper.

## The Attacker Moves Second: Stronger Adaptive Attacks Bypass Defenses Against LLM Jailbreaks and Prompt Injections

This paper is dated 10th October 2025 on Arxiv and comes from a heavy-hitting team of 14 authors - Milad Nasr, Nicholas Carlini, Chawin Sitawarin, Sander V. Schulhoff, Jamie Hayes, Michael Ilie, Juliette Pluto, Shuang Song, Harsh Chaudhari, Ilia Shumailov, Abhradeep Thakurta, Kai Yuanqing Xiao, Andreas Terzis, Florian Tramèr - including representatives from OpenAI, Anthropic, and Google DeepMind.

The paper looks at 12 published defenses against prompt injection and jailbreaking and subjects them to a range of "adaptive attacks" - attacks that are allowed to expend considerable effort iterating multiple times to try and find a way through.

The defenses did not fare well:

By systematically tuning and scaling general optimization techniques—gradient descent, reinforcement learning, random search, and human-guided exploration—we bypass 12 recent defenses (based on a diverse set of techniques) with attack success rate above 90% for most; importantly, the majority of defenses originally reported near-zero attack success rates.

Notably the "Human red-teaming setting" scored 100%, defeating all defenses. That red-team consisted of 500 participants in an online competition they ran with a $20,000 prize fund.

The key point of the paper is that static example attacks - single string prompts designed to bypass systems - are an almost useless way to evaluate these defenses. Adaptive attacks are far more powerful.

The three automated adaptive attack techniques used by the paper are:

Gradient-based methods - these were the least effective, using the technique described in the legendary Universal and Transferable Adversarial Attacks on Aligned Language Models paper from 2023.

Reinforcement learning methods - particularly effective against black-box models: "we allowed the attacker model to interact directly with the defended system and observe its outputs", using 32 sessions of 5 rounds each.

Search-based methods - generate candidates with an LLM, then evaluate and further modify them using LLM-as-judge and other classifiers.

The paper concludes somewhat optimistically:

Adaptive evaluations are therefore more challenging to perform, making it all the more important that they are performed. We again urge defense authors to release simple, easy-to-prompt defenses that are amenable to human analysis. Finally, we hope that our analysis here will increase the standard for defense evaluations, and in so doing, increase the likelihood that reliable jailbreak and prompt injection defenses will be developed.

Given how totally the defenses were defeated, I do not share their optimism that reliable defenses will be developed any time soon.

As a review of how far we still have to go this paper packs a powerful punch. I think it makes a strong case for Meta's Agents Rule of Two as the best practical advice for building secure LLM-powered agent systems today in the absence of prompt injection defenses we can rely on.

## Hacking the WiFi-enabled color screen GitHub Universe conference badge

I'm at GitHub Universe this week (thanks to a free ticket from Microsoft). Yesterday I picked up my conference badge which incorporates a full Raspberry Pi Pico microcontroller with a battery, color screen, WiFi and bluetooth.

GitHub Universe has a tradition of hackable conference badges - the badge last year had an eInk display. This year's is a huge upgrade though - a color screen and WiFI connection makes this thing a genuinely useful little computer!

The only thing it's missing is a keyboard - the device instead provides five buttons total: Up, Down, A, B, C. It might be possible to get a bluetooth keyboard to work though I'll believe that when I see it - there's not a lot of space on this device for a keyboard driver.

Everything is written using MicroPython, and the device is designed to be hackable: connect it to a laptop with a USB-C cable and you can start modifying the code directly on the device.

## Coding Like a Surgeon

A lot of people say AI will make us all "managers" or "editors" but I think this is a dangerously incomplete view!

Personally, I'm trying to code like a surgeon.

A surgeon isn't a manager, they do the actual work! But their skills and time are highly leveraged with a support team that handles prep, secondary tasks, admin. The surgeon focuses on the important stuff they are uniquely good at.

It turns out there are a LOT of secondary tasks which AI agents are now good enough to help out with. Some things I'm finding useful to hand off these days:

Before attempting a big task, write a guide to relevant areas of the codebase

Spike out an attempt at a big change. Often I won't use the result but I'll review it as a sketch of where to go

Fix typescript errors or bugs which have a clear specification

Write documentation about what I'm building

I often find it useful to run these secondary tasks async in the background, while I'm eating lunch, or even literally overnight!

When I sit down for a work session, I want to feel like a surgeon walking into a prepped operating room. Everything is ready for me to do what I'm good at.

## Claude Code Documentation Pattern

Something I'm enjoying about Claude Code is that any time you ask it questions about itself it runs tool calls to fetch its own documentation.

The claude_code_docs_map.md file is a neat Markdown index of all of their other documentation - the same pattern advocated by llms.txt. Claude Code can then fetch further documentation to help it answer your question.

I wish other LLM products - including both ChatGPT and Claude.ai themselves - would implement a similar pattern. It's infuriating how bad LLM tools are at answering questions about themselves, though unsurprising given that their model's training data pre-dates the latest version of those tools.

## Visual Features Across Modalities

New model interpretability research from Anthropic, this time focused on SVG and ASCII art generation.

We found that the same feature that activates over the eyes in an ASCII face also activates for eyes across diverse text-based modalities, including SVG code and prose in various languages. This is not limited to eyes – we found a number of cross-modal features that recognize specific concepts: from small components like mouths and ears within ASCII or SVG faces, to full visual depictions like dogs and cats.

These features depend on the surrounding context within the visual depiction. For instance, an SVG circle element activates "eye" features only when positioned within a larger structure that activates "face" features.

As a bonus, we also inspected features for an SVG of a pelican riding a bicycle, first popularized by Simon Willison as a way to test a model's artistic capabilities. We find features representing concepts including "bike", "wheels", "feet", "tail", "eyes", and "mouth" activating over the corresponding parts of the SVG code.

Now that they can identify model features associated with visual concepts in SVG images, can they use those for steering?

It turns out they can! Starting with a smiley SVG (provided as XML with no indication as to what it was drawing) and then applying a negative score to the "smile" feature produced a frown instead, and worked against ASCII art as well.

They could also boost features like unicorn, cat, owl, or lion and get new SVG smileys clearly attempting to depict those creatures.

## Tips for AI Coding Tools

Someone on Hacker News asked for tips on setting up a codebase to be more productive with AI coding tools. Here's my reply:

Good automated tests which the coding agent can run. I love pytest for this - one of my projects has 1500 tests and Claude Code is really good at selectively executing just tests relevant to the change it is making, and then running the whole suite at the end.

Give them the ability to interactively test the code they are writing too. Notes on how to start a development server (for web projects) are useful, then you can have them use Playwright or curl to try things out.

I'm having great results from maintaining a GitHub issues collection for projects and pasting URLs to issues directly into Claude Code.

I actually don't think documentation is too important: LLMs can read the code a lot faster than you to figure out how to use it. I have comprehensive documentation across all of my projects but I don't think it's that helpful for the coding agents, though they are good at helping me spot if it needs updating.

Linters, type checkers, auto-formatters - give coding agents helpful tools to run and they'll use them.

For the most part anything that makes a codebase easier for humans to maintain turns out to help agents as well.

Thought of another one: detailed error messages! If a manual or automated test fails the more information you can return back to the model the better, and stuffing extra data in the error message or assertion is a very inexpensive way to do that.

## The Python Software Foundation Withdraws Grant Application

The Python Software Foundation was recently "recommended for funding" for a $1.5m grant from the US government National Science Foundation to help improve the security of the Python software ecosystem, after a grant application process led by Seth Larson and Loren Crary.

The PSF's annual budget is less than $6m so this is a meaningful amount of money for the organization!

We were forced to withdraw our application and turn down the funding, thanks to new language that was added to the agreement requiring us to affirm that we "do not, and will not during the term of this financial assistance award, operate any programs that advance or promote DEI, or discriminatory equity ideology in violation of Federal anti-discrimination laws."

Our legal advisors confirmed that this would not just apply to security work covered by the grant - this would apply to all of the PSF's activities.

This was not an option for us. Here's the mission of the PSF:

The mission of the Python Software Foundation is to promote, protect, and advance the Python programming language, and to support and facilitate the growth of a diverse and international community of Python programmers.

If we accepted and spent the money despite this term, there was a very real risk that the money could be clawed back later. That represents an existential risk for the foundation since we would have already spent the money!

I was one of the board members who voted to reject this funding - a unanimous but tough decision. I'm proud to serve on a board that can make difficult decisions like this.

## Claude's Impact on Productivity

Claude doesn't make me much faster on the work that I am an expert on. Maybe 15-20% depending on the day.

It's the work that I don't know how to do and would have to research. Or the grunge work I don't even want to do. On this it is hard to even put a number on. Many of the projects I do with Claude day to day I just wouldn't have done at all pre-Claude.

Infinity percent improvement in productivity on those.

## Cursor Releases Composer-1

Cursor released Cursor 2.0 today, with a refreshed UI focused on agentic coding (and running agents in parallel) and a new model that's unique to Cursor called Composer 1.

The notable thing about Composer-1 is that it is designed to be fast. The pelican certainly came back quickly, and in their announcement they describe it as being "4x faster than similarly intelligent models".

It's interesting to see Cursor investing resources in training their own code-specific model - similar to GPT-5-Codex or Qwen3-Coder. From their post:

Composer is a mixture-of-experts (MoE) language model supporting long-context generation and understanding. It is specialized for software engineering through reinforcement learning (RL) in a diverse range of development environments.

Efficient training of large MoE models requires significant investment into building infrastructure and systems research. We built custom training infrastructure leveraging PyTorch and Ray to power asynchronous reinforcement learning at scale. We natively train our models at low precision by combining our MXFP8 MoE kernels with expert parallelism and hybrid sharded data parallelism, allowing us to scale training to thousands of NVIDIA GPUs with minimal communication cost.

During RL, we want our model to be able to call any tool in the Cursor Agent harness. These tools allow editing code, using semantic search, grepping strings, and running terminal commands. At our scale, teaching the model to effectively call these tools requires running hundreds of thousands of concurrent sandboxed coding environments in the cloud.

## MiniMax M2 Released

MiniMax M2 was released on Monday 27th October by MiniMax, a Chinese AI lab founded in December 2021.

It's a very promising model. Their self-reported benchmark scores show it as comparable to Claude Sonnet 4, and Artificial Analysis are ranking it as the best currently available open weight model according to their intelligence score:

MiniMax's M2 achieves a new all-time-high Intelligence Index score for an open weights model and offers impressive efficiency with only 10B active parameters (200B total).

The model's strengths include tool use and instruction following (as shown by Tau2 Bench and IFBench). As such, while M2 likely excels at agentic use cases it may underperform other open weights leaders such as DeepSeek V3.2 and Qwen3 235B at some generalist tasks. This is in line with a number of recent open weights model releases from Chinese AI labs which focus on agentic capabilities, likely pointing to a heavy post-training emphasis on RL.

The size is particularly significant: the model weights are 230GB on Hugging Face, significantly smaller than other high performing open weight models. That's small enough to run on a 256GB Mac Studio, and the MLX community have that working already.

MiniMax offer their own API, and recommend using their Anthropic-compatible endpoint and the official Anthropic SDKs to access it.

MiniMax are offering the new model via their API for free until November 7th, after which the cost will be $0.30/million input tokens and $1.20/million output tokens - similar in price to Gemini 2.5 Flash and GPT-5 Mini.

## Windsurf Releases SWE-1.5

Here's the second fast coding model released by a coding agent IDE in the same day - the first was Composer-1 by Cursor. This time it's Windsurf releasing SWE-1.5:

Today we're releasing SWE-1.5, the latest in our family of models optimized for software engineering. It is a frontier-size model with hundreds of billions of parameters that achieves near-SOTA coding performance. It also sets a new standard for speed: we partnered with Cerebras to serve it at up to 950 tok/s – 6x faster than Haiku 4.5 and 13x faster than Sonnet 4.5.

Like Composer-1 it's only available via their editor, no separate API yet. Also like Composer-1 they don't appear willing to share details of the "leading open-source base model" they based their new model on.

This one felt really fast. Partnering with Cerebras for inference is a very smart move.

They share a lot of details about their training process in the post:

SWE-1.5 is trained on our state-of-the-art cluster of thousands of GB200 NVL72 chips. We believe SWE-1.5 may be the first public production model trained on the new GB200 generation.

Our RL rollouts require high-fidelity environments with code execution and even web browsing. To achieve this, we leveraged our VM hypervisor otterlink that allows us to scale Devin to tens of thousands of concurrent machines. This enabled us to smoothly support very high concurrency and ensure the training environment is aligned with our Devin production environments.

That's another similarity to Cursor's Composer-1! Cursor talked about how they ran "hundreds of thousands of concurrent sandboxed coding environments in the cloud" in their description of their RL training as well.

This is a notable trend: if you want to build a really great agentic coding tool there's clearly a lot to be said for using reinforcement learning to fine-tune a model against your own custom set of tools using large numbers of sandboxed simulated coding environments as part of that process.

## Understanding Through Invention

To really understand a concept, you have to "invent" it yourself in some capacity. Understanding doesn't come from passive content consumption. It is always self-built. It is an active, high-agency, self-directed process of creating and debugging your own mental models.

## Marimo Joins CoreWeave

I don't usually cover startup acquisitions here, but this one feels relevant to several of my interests.

Marimo provide an open source (Apache 2 licensed) notebook tool for Python, with first-class support for an additional WebAssembly build plus an optional hosted service. It's effectively a reimagining of Jupyter notebooks as a reactive system, where cells automatically update based on changes to other cells - similar to how Observable JavaScript notebooks work.

The first public Marimo release was in January 2024 and the tool has "been in development since 2022".

CoreWeave are a big player in the AI data center space. They started out as an Ethereum mining company in 2017, then pivoted to cloud computing infrastructure for AI companies after the 2018 cryptocurrency crash. They IPOd in March 2025 and today they operate more than 30 data centers worldwide and have announced a number of eye-wateringly sized deals with companies such as Cohere and OpenAI.

Marimo's own announcement emphasizes continued investment in that tool:

Marimo is joining CoreWeave. We're continuing to build the open-source marimo notebook, while also leveling up molab with serious compute. Our long-term mission remains the same: to build the world's best open-source programming environment for working with data.

marimo is, and always will be, free, open-source, and permissively licensed.

## Rust Dependencies Coming to APT

I plan to introduce hard Rust dependencies and Rust code into APT, no earlier than May 2026. This extends at first to the Rust compiler and standard library, and the Sequoia ecosystem.

In particular, our code to parse .deb, .ar, .tar, and the HTTP signature verification code would strongly benefit from memory safe languages and a stronger approach to unit testing.

If you maintain a port without a working Rust toolchain, please ensure it has one within the next 6 months, or sunset the port.

## Claude Code Can Debug Low-level Cryptography

Go cryptography author Filippo Valsorda reports on some very positive results applying Claude Code to the challenge of implementing novel cryptography algorithms. After Claude was able to resolve a "fairly complex low-level bug" in fresh code he tried it against two other examples and got positive results both times.

Filippo isn't directly using Claude's solutions to the bugs, but is finding it useful for tracking down the cause and saving him a solid amount of debugging work:

Three out of three one-shot debugging hits with no help is extremely impressive. Importantly, there is no need to trust the LLM or review its output when its job is just saving me an hour or two by telling me where the bug is, for me to reason about it and fix it.

Using coding agents in this way may represent a useful entrypoint for LLM-skeptics who wouldn't dream of letting an autocomplete-machine writing code on their behalf.

## How to Use Every Claude Code Feature

Useful, detailed guide from Shrivu Shankar, a Claude Code power user. Lots of tips for both individual Claude Code usage and configuring it for larger team projects.

I appreciated Shrivu's take on MCP:

The "Scripting" model (now formalized by Skills) is better, but it needs a secure way to access the environment. This to me is the new, more focused role for MCP.

Instead of a bloated API, an MCP should be a simple, secure gateway that provides a few powerful, high-level tools: download_raw_data with filters, take_sensitive_gated_action with arguments, execute_code_in_environment_with_state with code.

In this model, MCP's job isn't to abstract reality for the agent; its job is to manage the auth, networking, and security boundaries and then get out of the way.

This makes a lot of sense to me. Most of my MCP usage with coding agents like Claude Code has been replaced by custom shell scripts for it to execute, but there's still a useful role for MCP in helping the agent access secure resources in a controlled way.

## PyCon US 2026 Call for Proposals

PyCon US is coming to the US west coast! 2026 and 2027 will both be held in Long Beach, California - the 2026 conference is set for May 13th-19th next year.

The call for proposals just opened. Since we'll be in LA County I'd love to see talks about Python in the entertainment industry - if you know someone who could present on that topic please make sure they know about the CFP!

The deadline for submissions is December 19th 2025. There are two new tracks this year:

PyCon US is introducing two dedicated Talk tracks to the schedule this year, "The Future of AI with Python" and "Trailblazing Python Security". For more information and how to submit your proposal, visit this page.

Now is also a great time to consider sponsoring PyCon.