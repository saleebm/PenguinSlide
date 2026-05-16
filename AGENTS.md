## MCP Agent Mail: coordination for multi-agent workflows

What it is
- A mail-like layer that lets coding agents coordinate asynchronously via MCP tools and resources.
- Provides identities, inbox/outbox, searchable threads, and advisory file reservations,
  with human-auditable artifacts in Git.

Why it's useful
- Prevents agents from stepping on each other with explicit file reservations (leases).
- Keeps communication out of your token budget by storing messages in a per-project archive.
- Offers quick reads (`resource://inbox/{Agent}?project=<abs-path>`, `resource://thread/{id}?project=<abs-path>`) and macros that bundle common flows.

How to use effectively
1) Register an identity: call ensure_project with this repo's absolute path as
   `human_key`, then call register_agent using that same absolute path as `project_key`.
2) Reserve files before you edit: file_reservation_paths(project_key, agent_name,
   paths=["src/**"], ttl_seconds=3600, exclusive=true)
3) Communicate with threads: use send_message(..., thread_id="FEAT-123"); check inbox
   with fetch_inbox and acknowledge with acknowledge_message.
4) Quick reads: resource://inbox/{Agent}?project=<abs-path>&limit=20

Macros vs granular tools
- Prefer macros for speed: macro_start_session, macro_prepare_thread,
  macro_file_reservation_cycle, macro_contact_handshake.
- Use granular tools for control: register_agent, file_reservation_paths, send_message,
  fetch_inbox, acknowledge_message.

Common pitfalls
- "sender or recipients not registered": register the sender first and verify recipient names in the correct project_key.
- "FILE_RESERVATION_CONFLICT": adjust patterns, wait for expiry, or use non-exclusive.
