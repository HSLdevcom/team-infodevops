# Our architectural principles

This document outlines the core principles that guide our technical decisions.
It is a living document that can be updated via pull request.
Every architectural decision record (ADR) should be aligned with these principles.

## 1. Open by default

By default, all source code, documentation, data and APIs we create should be published with an open license.

As a public sector organization, our work should be transparent.
Source code written with tax money should be owned and reusable by the public.
There are also benefits for HSL if others contribute to our open source projects.

Some might fund the collective work.
For example Fintraffic and Waltti provide the majority of the funding for Digitransit.

Some might provide effort, instead.
Moving funds between public sector organizations in different nations can get complicated and different cities and nations might have different needs.
For example OpenTripPlanner development occurs as collaboration between independently funded teams.

And some try new approaches completely independently enabling us to learn from them.

Because there is no friction of access control, open source code is also easier to find online and open documentation is easier to link to.

It is also hard to imagine in advance all the uses and benefits that can be achieved with a service.
As we must anyway secure our services, offering a web UI and open APIs to the public allows us to discover new use cases.
For example, we release GTFS and GTFS Realtime data so that others can build services for our passengers that we do not have the resources to build.
Or for example, it was originally debated whether to make Transitlog an internal service.
Instead, publishing the web UI and allowing anonymous usage enabled all parts of HSL, other organizations and our customers to use the service for their needs.

Many smaller public sector organizations do not have enough expertise to recognize what they should be demanding from their vendors.
The public sector organizations can be tricked to accept closed-source licensing even when they are paying for the creation and development of the software or when the vendor has made only trivial proprietary contributions to a permissively licensed open source product.

We can help those public sector organizations with our licensing choices by preventing such capture of the commons.
Copyleft licenses require new developers to publish their improvements to the commons, while permissive licenses only require attributing the creator.
Copyleft licenses prevent any one vendor from capturing the market around that product.
Copyleft licenses move the market towards a competitive, multi-vendor service economy where many companies can offer services including development, maintenance, hosting, training, support, consulting and coaching for the same copyleft product.

When we publish our code as open source, it also lessens the cost we have to pay for our development tools.
For example, many hosting and static analysis services offer free services for open source projects.

Therefore, we generally lean towards `AGPL-3.0-only` or `EUPL-1.2` for source code.
When we fix our dependencies, we contribute using the licenses of those dependencies.

On the other hand, data behaves differently.
It's hard to know in advance how to combine data usefully.
Some share-alike licenses might clash with our strategy and what we wish to achieve.

For example, we wish to use the OpenStreetMap (OSM) data for its superior, timely accuracy.
OSM is released under the share-alike Open Database License (ODbL).
However, to serve passengers through many applications, we also wish for the global proprietary services such as Google Maps to be able to use our data.
Google would not use our data if it would force them to release their own map data under ODbL.
If Google Maps users would not be offered public transport services, they might choose to use private cars or taxis more often.
That is why we do not release our GTFS package under a share-alike license.

For most of our data, we use a permissive license.
`CC0` or `CC-BY-4.0` fit data and documentation.

There can be exceptions to licensing openly.
Such exceptions must have a compelling reason.
For example, infrastructure secrets and personal information should be kept secret.

## 2. Favor open source tools and dependencies

We prefer using open source tools and service dependencies over proprietary, closed-source alternatives.
This reduces costs and allows for greater control and customization.

Additionally, public sector organizations are especially vulnerable to vendor lock-in as the legally mandated procurement processes typically take from months to years to even get the procured work started.
The migration process away from a closed-source product to another product includes planning for the change, designing the procurement process, running the procurement process until we have a contract with a new vendor, starting migration work and finally finishing the migration work.
For any significant product that is almost guaranteed to take years.

If we would use a proprietary product to support our core business processes, any of the following would cause significant rises in costs or terrible service level drops for our customers: our needs or what is required of us change beyond what the product offers; the vendor changes their pricing structure and significantly raises what they charge from us; the vendor changes the design and direction of the product to no longer match our needs; the vendor sunsets the product; or the vendor simply goes out of business.

In contrast, the migration process for an open-source product can be solved in many ways: start self-hosting; switch to another service provider for the same product; pay someone else than the previous vendor for active development; or pay someone for just the critical security fixes while migrating to another service.
Notice the lack of monopoly power on the side of the vendors.

We will use managed open source services, e.g., managed PostgreSQL, when the operational benefits and costs are attractive, but the underlying technology should remain open to retain our degrees of freedom.
Beware using proprietary parts of APIs of hosted open core services.

## 3. Use boring technology

Due to how slowly a public sector organization reacts to change in terms of procurement, we choose well-understood, reliable, and proven technologies over new and unproven ones.

Our goal is to build stable, maintainable systems that are easy for our team to operate.
We prioritize predictability over novelty.
This allows us to focus on solving business problems.

In other words, we do not want to bet the house on a technology startup that goes bankrupt and takes its service down quickly.
Our strategy is to wait for the market to settle down.

We should make a limited amount of exciting choices.

For more, see Dan McKinley's talk on the topic[[1]](#ref1).

## 4. Consider the lifecycle of products

We usually do not know in advance when we will stop using a product.
But we can prepare for the end in advance.

The easiest time to do that is before starting to use a new technology.
We should figure out how to get rid of a product before we start using it.
Understand how the data is structured, how it can be copied elsewhere and how it can be transformed and fed into another product.

Take the long-term view.

## 5. Use the agile mindset

We use the agile mindset by adapting to change, delivering value incrementally, pursuing faster feedback and reflecting and improving on our ways of working.

## 6. Prioritize quality

Hundreds of thousands of people rely on our systems every day to get to where they need to be.
That is why we must maintain a high standard of quality in our work.

We choose rather a few carefully curated features with few bugs than many features with many bugs.

Aim to exclude categories of bugs rather than individually hunting them down later.

We do not keep accumulating bugs in our issue tracker and move on to the next feature.
Instead, we prioritize fixing bugs as they are found to prevent technical neglect.

Refactoring belongs to most development tasks.

With prototypes, proof of concepts, spikes and riskiest assumption tests we aim to learn more.
Then we should understand balance learning with reusability of code.

## 7. Shift left

The learn sooner of problems and to increase the quality of our software, we use tools that help us catch problems as soon as possible.
That includes checking our work with extensive automatic formatting, linting, quality scanning, security scanning, compiling with warnings as errors and testing in different ways.

Pair or mob work moves the peer review to the design and coding phase.

The CI enforces that the default branch stays green.

We also update our dependencies in a timely manner.

## 8. Use a functional style

To ease testing and quality assurance, learn from functional programming:

1. Make illegal states unrepresentable. Use algebraic data types to cover all options exhaustively. Parse into valid types as early as possible instead of validating at the point of use.
2. Separate pure functions, e.g. the business logic, from impure functions doing I/O, e.g. HTTP requests, database access or printing on screen. Minimize the proportion of I/O code.

## References

<a name="ref1">[1]</a>: McKinley, D. (2018). Choose boring technology. <https://boringtechnology.club/>.
