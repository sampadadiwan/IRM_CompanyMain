# Hermes Agent Multi-Tenant Architecture

This document outlines the architecture for integrating [Hermes Agent](https://github.com/nousresearch/hermes-agent) into the IRM SaaS platform as a multi-tenant service.

## Overview

The goal is to provide each tenant with a dedicated, isolated, and persistent AI agent that can work on their specific data (investors, KPIs, portfolios) via APIs and database access, while ensuring strict security boundaries and easy portability between servers.

## High-Level Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                        Your Rails SaaS                          │
│                                                                 │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────────────┐ │
│  │ Tenant Mgmt  │  │ Agent Orchestrator│  │ MCP API Gateway   │ │
│  │ (existing)   │  │ (new pack)       │  │ (new Rails engine)│ │
│  └──────┬───────┘  └────────┬─────────┘  └────────┬──────────┘ │
│         │                   │                      │            │
│         ▼                   ▼                      ▼            │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────────────┐ │
│  │ tenants      │  │ agent_instances  │  │ /api/mcp/tenant/:id│ │
│  │ agent_configs│  │ agent_profiles   │  │ (scoped by tenant)│ │
│  └──────────────┘  └──────────────────┘  └───────────────────┘ │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────────┐
        │ Docker   │ │ S3       │ │ Hermes Agent │
        │ Compose  │ │ Backups  │ │ Containers   │
        │ Manager  │ │ (per     │ │ (1 per       │
        │          │ │ tenant)  │ │ tenant)      │
        └──────────┘ └──────────┘ └──────────────┘
              │
              ▼
        ┌──────────────┐
        │ SQLite Sync  │
        │ (Read-Only   │
        │ Analysis DB) │
        └──────────────┘
```

## Key Design Decisions

### 1. One Container Per Tenant
**Rationale**: Unlike Hermes "Profiles" which share a process and parent directory, dedicated containers provide:
- **Strong Isolation**: Faults or security breaches in one agent cannot affect others.
- **Resource Control**: CPU and memory limits can be enforced per tenant.
- **Portability**: Containers can be moved across a cluster independently.

### 2. MCP as the Data Access Layer
**Rationale**: Direct database access for AI agents is high-risk.
- **Controlled Surface**: The Rails app exposes a specific [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server.
- **Tenant Scoping**: The MCP server enforces `entity_id` scoping on every query.
- **Auditability**: Every tool call (query or update) is logged in the Rails database.

### 3. Read-Only Analysis Layer (SQLite)
**Rationale**: For complex data analysis (joins, aggregations, pandas), API calls are too slow and token-heavy.
- **High Performance**: Each agent gets a local SQLite snapshot of the tenant's data.
- **Read-Only Enforcement**: The DB file is mounted into the container as a **read-only volume** (`:ro`).
- **Discarded Writes**: Any attempt by the agent to write to this DB will fail at the OS level, ensuring the source of truth remains in the main Rails DB.

### 4. S3 for State Persistence
**Rationale**: Hermes stores state (sessions, memories, skills) in a local SQLite database and markdown files.
- **Artifact Management**: The entire `~/.hermes` directory is treated as a state artifact.
- **Disaster Recovery**: Agents can be restored to any server from the latest S3 backup.

---

## Component Details

### 1. Agent Orchestrator Service
The Orchestrator is the central brain for managing agent lifecycles. It interacts with the Docker daemon and the filesystem to ensure each tenant has a healthy, isolated environment.

*   **Provisioning Flow**:
    1.  **Key Generation**: Creates a unique `MCP_API_KEY` for the tenant.
    2.  **Directory Setup**: Creates `/opt/hermes-agents/{tenant_slug}/` with subdirectories for `data`, `skills`, and `backups`.
    3.  **Config Generation**: Generates `config.yaml` and `.env` with tenant-specific settings (MCP URL, API keys, model selection).
    4.  **Docker-Compose Generation**: Writes a tenant-specific `docker-compose.yml` with resource limits and volume mounts.
    5.  **Container Start**: Executes `docker-compose up -d`.
*   **Lifecycle Management**:
    *   **Health Checks**: Periodically pings the agent's gateway or checks container status.
    *   **Resource Enforcement**: Applies `cpus: "1.0"` and `memory: 2G` limits to prevent a single agent from starving the host.
    *   **Auto-Restart**: Configures Docker to restart containers unless explicitly stopped.

### 2. Agent Data Exporter (SQLite Sync)
This component bridges the gap between the main Rails production DB and the agent's local analysis environment.

*   **Export Pipeline**:
    1.  **Scoped Query**: Runs `SELECT * FROM table WHERE entity_id = ?` for all relevant tables (Investors, KPIs, Portfolios, etc.).
    2.  **Transformation**: Converts ActiveRecord results into a format suitable for SQLite import.
    3.  **SQLite Build**: Creates a fresh SQLite database file using a predefined schema that mirrors the relevant parts of the Rails schema.
*   **Sync Strategy**:
    1.  **Atomic Swap**: The new `.sqlite` file is written to a temporary location and then moved (`mv`) to the final location mounted by the container. This ensures the agent never reads a partially written file.
    2.  **Notification**: Optionally sends a signal to the agent (via MCP) to refresh its database connection.

### 3. MCP Server (Rails Engine)
The MCP server is the secure gateway for all "write" operations and real-time "read" operations that require the latest production state.

*   **Protocol Handling**: Implements the JSON-RPC 2.0 protocol over HTTP.
*   **Security Middleware**:
    *   **Authentication**: Validates the `X-MCP-API-Key` header.
    *   **Tenant Scoping**: Automatically sets the `current_tenant` and `current_entity` based on the API key.
    *   **Authorization**: Every tool call is passed through a Pundit policy (e.g., `McpToolPolicy#query_kpis?`).
*   **Tool Registry**: Dynamically advertises available tools to the agent based on the tenant's subscription level and permissions.

### 4. S3 Backup & Restore
Ensures that an agent's "learned" state (memories, skills, conversation history) is never lost.

*   **Backup Process**:
    1.  **Quiesce**: Optionally sends a signal to the agent to flush its state to disk.
    2.  **Tarball**: Creates a compressed archive of the `~/.hermes` directory.
    3.  **Upload**: Streams the archive to S3 with a key pattern: `backups/{tenant_id}/{timestamp}.tar.gz`.
*   **Restore Process**:
    1.  **Download**: Fetches the requested backup from S3.
    2.  **Extract**: Untars the archive into the tenant's local data directory.
    3.  **Start**: Orchestrator starts the container, which picks up the restored state.

---

## Detailed Sequence Diagrams

### 1. Tenant Onboarding & Provisioning
```text
User        Rails UI      Orchestrator    Data Exporter    Docker Host      S3
 │            │             │               │               │             │
 ├─Enable AI─▶│             │               │               │             │
 │            ├─Create Job─▶│               │               │             │
 │            │             ├─Gen Keys/Cfg─▶│               │             │
 │            │             │               ├─Export Data──▶│             │
 │            │             │               │ (SQLite RO)   │             │
 │            │             ├─Gen Compose──▶│               │             │
 │            │             │               │               │             │
 │            │             ├─Docker Up────▶│               │             │
 │            │             │               │               │             │
 │            │             ├─Initial Bkp───┼───────────────┼────────────▶│
 │            │             │               │               │             │
 │            │◀──Success───┤               │               │             │
 │◀──Ready────┤             │               │               │             │
```

### 2. Data Analysis Flow (SQLite)
```text
Hermes Agent    Local SQLite DB    Docker Host FS
     │               │                  │
     ├─SQL Query────▶│                  │
     │ (Read-Only)   │                  │
     │               │                  │
     │◀──Results─────┤                  │
     │               │                  │
     ├─Pandas Proc──▶│                  │
     │               │                  │
     ├─Attempt Write─┼─────────────────▶│
     │               │                  │
     │◀──Permission Denied (EPERM)──────┤
```

### 3. Write Operation Flow (MCP)
```text
Hermes Agent    MCP Server (Rails)    Main DB        Audit Log
     │               │                  │               │
     ├─Tool Call────▶│                  │               │
     │ (JSON-RPC)    ├─Auth & Scope────▶│               │
     │               │                  │               │
     │               ├─Pundit Check────▶│               │
     │               │                  │               │
     │               ├─Execute Write───▶│               │
     │               │                  │               │
     │               ├─Log Action───────┼──────────────▶│
     │               │                  │               │
     │◀──Success─────┤                  │               │
```

### 4. Backup & Migration Flow
```text
Admin UI      Orchestrator    Host A (Old)      S3        Host B (New)
 │               │               │             │             │
 ├─Migrate──────▶│               │             │             │
 │               ├─Stop Agent───▶│             │             │
 │               │               │             │             │
 │               ├─Backup State──┼────────────▶│             │
 │               │               │             │             │
 │               ├─Restore State─┼─────────────┼────────────▶│
 │               │               │             │             │
 │               ├─Start Agent───┼─────────────┼────────────▶│
 │               │               │             │             │
 │◀──Complete────┤               │             │             │
```

---

## Security Model

| Layer | Security Control |
|-------|------------------|
| **Network** | Containers only have access to the Rails MCP API and the LLM provider. |
| **Data** | MCP server enforces strict multi-tenancy scoping via `entity_id`. |
| **Analysis DB** | SQLite file is mounted as **Read-Only** (`:ro`). Writes are impossible. |
| **Execution** | Docker containers run with dropped capabilities and no-new-privileges. |
| **Audit** | Every interaction is logged; write operations require explicit allowlisting. |

## Operational Flows

### Tenant Onboarding
1. Tenant enables "AI Assistant" in settings.
2. Rails triggers `AgentProvisioningJob`.
3. **Data Export**: `AgentDataExporter` creates the initial SQLite analysis DB.
4. Orchestrator generates keys, starts Docker container (mounting the SQLite DB as RO), and performs initial S3 sync.

### Data Refresh (Sync)
1. Scheduled job (e.g., every 4 hours or on-demand) triggers `AgentDataExporter`.
2. New SQLite snapshot is generated.
3. Snapshot is swapped into the agent's data directory.
4. Agent is notified (via MCP or signal) that new data is available.

### Backup Strategy
- **Daily**: Staggered backups of all active agents to S3.
- **On-Stop**: Automatic backup whenever an agent is gracefully shut down.

### Migration
1. Stop agent on Host A.
2. Final backup to S3.
3. Provision on Host B using the S3 backup.
4. Update routing to point to Host B.

## Implementation Phases

1. **Phase 1: Foundation**: Build the `AgentInstance` models and Docker management logic.
2. **Phase 2: Data Gateway**: Implement the Rails MCP server with core data tools.
3. **Phase 3: Persistence**: Implement S3 backup/restore and automated provisioning.
4. **Phase 4: UI & Monitoring**: Build the admin dashboard and tenant-facing controls.
