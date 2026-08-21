# The role you guess is not the role you need

Scoping the provisioning credential meant writing down which Proxmox privileges the
provider actually uses. The first list was assembled by reading what the configuration
does — create a VM, allocate a disk, upload a file — and mapping that to privilege
names. It was wrong in three different ways, and each was wrong for a different reason.

## `VM.Monitor` does not exist any more

It is in plenty of guides. Proxmox VE 9 rejects it when the role is created. A privilege
name that was correct for years can be renamed or removed, and a guide does not know
which version you are on. The equivalent here was `VM.GuestAgent.Audit`.

Failure mode: loud and immediate, at role creation. The cheap kind.

## `Datastore.Allocate` was needed only at `/storage/local`

Without it the snippets directory was simply **not listed** — the API returned a
successful response with the file missing from it, rather than a 403. A privilege can be
missing without producing a permission error, if the thing it guards is a listing.

Granting it at `/storage/local` then broke reads that had worked, because a deeper ACL
path replaces the inherited permissions rather than adding to them
([301 · ACL paths override, not add](301-acl-paths-override-they-do-not-add.md)). Both
roles have to be named at the deeper path.

Failure mode: silent. The worst kind.

## `Sys.AccessNetwork` was invisible until an apply ran

Downloading a cloud image needs it, because the node queries the source URL for metadata
before fetching. Nothing in the configuration mentions the network. Nothing in `tofu
plan` touches it — plan reads, and this is a write. It surfaced as an HTTP 403 partway
through `make rebuild`, which is destroy-then-apply, so the destroy had already
succeeded and the cluster stayed down until the privilege was added
([301 · under-scoping fails mid-apply](301-under-scoping-fails-mid-apply.md)).

Failure mode: loud, but expensive, because of *when* it arrived.

## What the gap is actually made of

The final role holds nineteen privileges. The interesting number is not nineteen, it is
that **the three corrections could not have been found by reading anything.** One needed
the target version, one needed to notice an absence rather than an error, and one needed
a write to actually be attempted.

The method that works is the opposite of the one that feels responsible: start with too
little, run the real operation, and add what it refuses. Deriving the list up front
produces a plausible list, and plausible is indistinguishable from correct until
something fails.

Two practical consequences:

- **A passing `plan` proves nothing about a credential.** Plan reads; apply writes.
- **Sequence the first run so failure is cheap.** Applying into empty state surfaces the
  identical error with nothing torn down. Testing with destroy-then-apply put the
  cluster's existence on the line to learn something an apply alone would have taught.

## Where this bites next

`make check-privileges` asserts the role by **equality** — a privilege appearing is a
widening, one disappearing breaks provisioning, and the list is the record of what was
learned. If the configuration grows a resource that touches something new, expect
another 403, and expect it during apply.
