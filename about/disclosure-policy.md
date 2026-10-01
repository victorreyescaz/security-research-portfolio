# Disclosure policy

The rules I apply to client material in this repository. They exist so that a
prospective client can see how their code would be handled before they hand
it over.

## Principles

**Nothing is published without written permission.** Not the report, not the
contract source, not a proof of concept, and not a "generalized" or
anonymized write-up of the vulnerability pattern either. A pattern write-up
that a reader can map back to an identifiable protocol is a disclosure.

**Nothing is published while the vulnerability is open.** A working exploit
against an unpatched protocol is an attack tool, regardless of the intent of
the person publishing it. Permission to use an engagement as portfolio
material is treated as taking effect only once the findings are actually
resolved.

**Permission is specific, not general.** Approval to publish one engagement
says nothing about the next one, and approval to publish a report says
nothing about publishing the source code. Each is asked for separately, and
the scope granted is recorded with the engagement it covers.

**The client sets the timing.** If a client prefers to wait until launch, or
until an external audit completes, or indefinitely, that decision stands
without negotiation.

## How the process runs

1. Findings are reported privately to the client as they are confirmed, with
   reproduction steps. Nothing waits for the final report.
2. Remediation is tracked per finding until the exploit no longer reproduces
   and a regression test covers it.
3. Once findings are closed, I ask in writing for portfolio permission, and
   state precisely what I would publish: report, source code, exploits, or
   some subset.
4. Only after that permission arrives does anything become public. What was
   agreed is recorded next to the material itself.

## While material is unpublished

Work in progress lives in a **private** repository. Nothing about an
unresolved finding (report, source, or reproduction) leaves the channel
agreed with the client.

## Findings outside a client engagement

For findings in code I was not engaged to review, I follow the program's own
disclosure policy where one exists. Where none exists, I contact the
maintainers privately first and agree the timing of any public write-up with
them before publishing.
