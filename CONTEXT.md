# LessonMeld Product Context

LessonMeld combines private local lesson authoring with an optional hosted community where deliberately published learning content can be shared. This glossary names the product concepts consistently across both surfaces.

## Authoring and publication

**Lesson Project**:
A private local bundle containing source recordings, editing decisions, annotations, transcripts, settings, and export metadata.
_Avoid_: Cloud project, hosted project

**Publication**:
An explicit transfer of selected lesson metadata and derived assets from a Lesson Project into one Tenant. A Publication is a hosted copy, not synchronization of the private source project.
_Avoid_: Sync, upload project

**Media Asset**:
A hosted object deliberately attached to community content, such as a published lesson video, image, caption file, replay, or downloadable resource.
_Avoid_: Project media, raw capture

## Tenancy and identity

**Tenant**:
The isolation and ownership boundary for one hosted community, its members, content, configuration, entitlements, and audit history.
_Avoid_: Account, workspace, organization

**Community**:
The member-facing experience owned by one Tenant. The first launch may contain one Community, but the domain remains tenant-aware.
_Avoid_: Tenant, site

**Identity**:
An externally authenticated login principal that can be bound to one or more Members. Credential truth belongs to the identity provider.
_Avoid_: User, account

**Member**:
A person's tenant-owned participation record, including status, roles, profile, preferences, entitlements, and content ownership.
_Avoid_: User, identity, account

**Profile**:
The member-controlled public or tenant-visible presentation of a Member.
_Avoid_: Member, identity

**Role**:
A tenant-scoped named collection of Permissions assigned to Members.
_Avoid_: Member type, admin flag

**Permission**:
A tenant-scoped authorization capability evaluated against a resource and its ownership or visibility.
_Avoid_: Role, access level

**Segment**:
A saved tenant-scoped member selection defined by explicit membership or evaluated attributes.
_Avoid_: Role, group

## Community content

**Space**:
A tenant-scoped container that defines membership, visibility, navigation, and content policy for discussions, courses, events, or channels.
_Avoid_: Group, category

**Post**:
A member-authored top-level content item published within a Space.
_Avoid_: Discussion, article

**Comment**:
A reply attached to a Post or another Comment within the same Space and visibility boundary.
_Avoid_: Message, post

**Reaction**:
A lightweight member response to one supported content item.
_Avoid_: Vote, rating

**Channel**:
A Space-scoped or tenant-scoped destination for ordered real-time Messages.
_Avoid_: Discussion, direct message

**Conversation**:
A private ordered message stream whose participants are explicit Members.
_Avoid_: Channel, space

**Message**:
One immutable member-authored entry in a Channel or Conversation, with edits and moderation recorded separately.
_Avoid_: Post, comment

**Chat**:
The member-facing capability formed by Channels, Conversations, and Messages; it is not a separate owned record.
_Avoid_: Using chat as a synonym for a channel, conversation, or message

## Learning and events

**Course**:
A tenant-owned learning offering composed of an ordered Curriculum and enrollment policy.
_Avoid_: Lesson, publication

**Curriculum**:
The ordered structure of Modules and Lessons within a Course.
_Avoid_: Course content, syllabus file

**Lesson**:
A hosted learning unit that can reference a Publication and other tenant-owned resources.
_Avoid_: Lesson Project, course

**Enrollment**:
A Member's tenant-scoped participation record in a Course.
_Avoid_: Membership, entitlement

**Progress**:
The append-derived record of a Member's completion and position within one Enrollment.
_Avoid_: Analytics event, grade

**Event**:
A scheduled tenant-owned member experience with visibility, capacity, hosts, and attendance policy.
_Avoid_: Domain event, live room

**RSVP**:
A Member's current attendance intent for one Event.
_Avoid_: Enrollment, ticket

**Live Session**:
The time-bounded interactive room associated with an Event.
_Avoid_: Event, replay

**Replay**:
A published Media Asset produced from a completed Live Session.
_Avoid_: Recording, lesson project

## Commerce and entitlements

**Offering**:
A tenant-owned sellable or grantable package that produces one or more Entitlements.
_Avoid_: Product, membership

**Price**:
A currency, amount, billing cadence, and eligibility rule attached to an Offering.
_Avoid_: Plan, payment

**Entitlement**:
A tenant-scoped grant that authorizes a Member to access a resource or capability for a defined period.
_Avoid_: Role, purchase, enrollment

**Purchase**:
The tenant record of a completed one-time commercial transaction.
_Avoid_: Payment, entitlement

**Subscription**:
The tenant record of a recurring commercial agreement and its lifecycle.
_Avoid_: Membership, entitlement

**Coupon**:
A tenant-defined rule that adjusts eligible Prices without changing the underlying Offering.
_Avoid_: Credit, entitlement

## Recognition and acquisition

**Challenge**:
A tenant-owned, time-bounded set of participation criteria that can produce an Award or Reward.
_Avoid_: Workflow, campaign

**Badge**:
A tenant-owned recognition definition with a stable identity and presentation.
_Avoid_: Award, role

**Award**:
An immutable grant of a Badge to a Member with the qualifying reason and time.
_Avoid_: Badge, entitlement

**Leaderboard**:
A ranked, time-bounded projection of eligible participation facts within one Tenant or Space.
_Avoid_: Score record, analytics dashboard

**Reward**:
A benefit granted to a Member from an explicit rule or decision, represented by an Entitlement when it controls access.
_Avoid_: Badge, role

**Site**:
A tenant-owned public web presence containing Pages, navigation, branding, and Domain Mappings.
_Avoid_: Community, tenant

**Page**:
A versioned tenant-authored arrangement of approved content blocks within a Site.
_Avoid_: Post, lesson

**Domain Mapping**:
A verified association between a Tenant Site and a custom hostname.
_Avoid_: Tenant, site

## Operations, trust, and integration

**Notification**:
A tenant-owned delivery request created from a domain event for one Member and channel.
_Avoid_: Message, broadcast

**Digest**:
A scheduled aggregation of eligible Notifications for one Member.
_Avoid_: Broadcast, newsletter

**Broadcast**:
A tenant-authored outbound communication sent to an explicit audience or Segment.
_Avoid_: Notification, message

**Form**:
A tenant-owned versioned data-collection definition with explicit purpose, consent, field retention, and audience.
_Avoid_: Page, survey response

**Submission**:
One immutable response to a Form, associated with a Member or permitted external contact when policy allows.
_Avoid_: Profile, message

**Workflow**:
A tenant-owned automation definition that maps supported Triggers to constrained Actions.
_Avoid_: Script, integration

**Domain Event**:
An immutable fact emitted after a successful domain state change and used for downstream product behavior.
_Avoid_: Audit event, analytics event

**Audit Event**:
An immutable security and administration record describing who attempted or performed a sensitive action against which tenant resource.
_Avoid_: Domain event, log line

**Moderation Case**:
A tenant-owned review record joining reports, evidence references, decisions, sanctions, and appeals.
_Avoid_: Report, support ticket

**Integration**:
A tenant-authorized connection to an external system with explicit scopes, credentials, and lifecycle.
_Avoid_: Workflow, webhook

**Export**:
A tenant-generated portable representation of owned data for backup, migration, or a member rights request.
_Avoid_: Publication, connector package

**Generated Suggestion**:
AI-produced content that remains attributed, reviewable, and non-authoritative until a Member accepts it.
_Avoid_: Decision, automated moderation action
