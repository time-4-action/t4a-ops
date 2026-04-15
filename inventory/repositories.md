# Repository Inventory

| Repository | Purpose | Primary Language | Deploy Target | CI/CD |
|-----------|---------|-----------------|---------------|-------|
| `t4a-ops` | Infrastructure & ops source of truth | Markdown / Shell | — | — |
| `patrik-metakocka-automation-api` | Metakocka ERP sync API (warehouse, invoices) | Node.js | t4a-t2 (Docker) | Docker Hub `etiamsi/patrik-metakocka-automation-api` |
| `patrik-products-automation` | Product catalog automation & sync | Node.js | t4a-t2 (Docker) | Docker Hub `etiamsi/patrik-products-automation` |
| `patrik-products-ui` | Product management & export UI | Node.js | t4a-t2 (Docker) | Docker Hub `etiamsi/patrik-products-ui` |
| `t4a-admin` | Admin dashboard (Next.js + Auth0) | TypeScript | t4a-t2 (Docker) | Docker Hub `etiamsi/t4a-admin` |
| `t4a-ai-agent-ui` | AI agent chat interface (Next.js + Auth0) | TypeScript | t4a-t2 (Docker) | Docker Hub `etiamsi/t4a-ai-agent-ui` |
| `t4a-export-api` | Product export API | Node.js | t4a-t2 (Docker) | Docker Hub `etiamsi/t4a-export-api` |
| `t4a-mcp` | MCP server — AI search (FastAPI + ChromaDB + BM25) | Python | t4a-t2 (Docker) | Docker Hub `etiamsi/t4a-mcp` |

> **Instructions:** Add one row per repository in the T4A ecosystem (~20 repos).
