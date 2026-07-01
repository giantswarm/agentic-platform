# Authentication flow

How a request authenticates against the agentic platform. This document covers
**only authentication** — TLS termination details and the broader
networking/NetworkPolicy model are described elsewhere (`README.md` →
*Ingress topology* and the `networkpolicy-dataplane-*` templates).

The request topology is selected by `ingress.mode` (see `README.md` →
*Ingress topology*):

- **`muster-direct`** (default) — client → muster directly. There is **one** hop:
  the public Gateway → muster. No agentgateway data plane exists.
- **`agentgateway-muster`** / **`agentgateway-direct`** — client → agentgateway
  `/mcp` → muster (or, in `agentgateway-direct`, the servers). Here a second
  Gateway API hop (agentgateway) sits in front of muster.

This document narrates the **`agentgateway-*`** topology, where agentgateway is
present. In `muster-direct` mode, drop the agentgateway hop: the client reaches
muster directly over the public hop and muster enforces OAuth exactly as
described below.

Each section is one slice of the story with its own diagram:

1. [The request path (who terminates what)](#1-the-request-path)
2. [OAuth discovery — how an unauthenticated client finds the auth server](#2-oauth-discovery)
3. [Token handling at muster — `forward` vs `exchange`](#3-token-handling-at-muster)
4. [Edge JWT validation (`oauthMode: validate`) and JWKS](#4-edge-jwt-validation-and-jwks)

In the `agentgateway-*` modes, the only URL a client is ever given is
**`agentgateway.<cluster>.<base>/mcp`**; muster is a backend implementation
detail and clients never address it for `/mcp`. In `muster-direct` mode the
client is given muster's own `/mcp` URL directly.

---

## 1. The request path

In the `agentgateway-*` modes, two Gateway API hops sit in front of muster. The
**public** hop terminates TLS and owns the hostname; the **agentgateway** hop is
the observability and policy choke point. Authentication itself is still
enforced by muster at the end. (In `muster-direct` mode only the public hop
exists, routing straight to muster.)

```mermaid
flowchart LR
    client["MCP client<br/>(Claude.ai, Claude Code, any SDK)"]

    subgraph envoy["envoy giantswarm-default · envoy-gateway-system"]
        tls["TLS termination<br/>public hostname"]
        btp["route-scoped BackendTrafficPolicy<br/>preserves WWW-Authenticate · requestTimeout 0s"]
    end

    subgraph ns["release namespace"]
        agw["agentgateway proxy :8080<br/>observability choke point<br/>auth.passthrough by default"]
        muster["muster :8090/mcp<br/>OAuth enforcement + MCP aggregation"]
    end

    client -->|"HTTPS  /mcp"| tls
    tls --> btp
    btp -->|"HTTPRoute → Service :8080"| agw
    agw -->|"AgentgatewayBackend"| muster
```

What each component is responsible for, in auth terms:

| Hop | Template | Auth responsibility |
|---|---|---|
| envoy `giantswarm-default` | (cluster ingress, not this chart) | Terminates TLS, owns the public hostname. |
| `HTTPRoute` (`/mcp`) | `templates/agentgateway/httproute.yaml` | Routes `/mcp` to the agentgateway Service:8080. Rendered in the `agentgateway-*` modes (`ingress.mode`); reads `ingress.parentRefs` / `ingress.hostnames`. Without it the agentgateway `/mcp` route does not exist. (muster's public `/` route, `templates/ingress/muster-httproute.yaml`, is always rendered.) |
| `BackendTrafficPolicy` | `templates/agentgateway/backendtrafficpolicy.yaml` (agentgateway `/mcp` route) and `templates/ingress/muster-backendtrafficpolicy.yaml` (muster `/` route) | **Critical for auth:** a cluster-wide error-pages `BackendTrafficPolicy` rewrites 4xx/5xx to branded HTML and strips upstream headers — including `WWW-Authenticate`. A route-scoped policy (enabled via `ingress.backendTrafficPolicy.enabled`) takes precedence and preserves muster's `401 … WWW-Authenticate` challenge, without which clients cannot discover where to authenticate. The umbrella renders one over the agentgateway `/mcp` route (`agentgateway-*` modes only) and a complementary one over muster's `/` route (**all** modes) — the latter matters in `muster-direct`, where muster serves `/mcp` directly. Both also set `requestTimeout: 0s` (`ingress.backendTrafficPolicy.timeout`) so long-lived MCP/SSE streams are not killed. |
| agentgateway proxy | `gateway.yaml` + `agentgatewayparameters.yaml` | By default `auth.passthrough` — forwards the bearer token to muster unvalidated. Optionally validates at the edge (§4). |
| muster | `muster` sub-chart | Enforces OAuth, validates the token, aggregates downstream MCP servers, and performs token exchange where needed (§3). |

---

## 2. OAuth discovery

A fresh client arrives with no token. It must discover the authorization server
before it can authenticate. In the `agentgateway-*` modes the challenge is
served by muster but must survive the journey back through both gateway hops —
that is what the route-scoped `BackendTrafficPolicy` (`ingress.backendTrafficPolicy`)
guarantees. (In `muster-direct` mode the challenge travels only the single
public hop, but muster's `/` route still carries its own route-scoped
`BackendTrafficPolicy` so the same cluster-wide error-pages policy cannot strip
`WWW-Authenticate` from the `401` muster serves on `/mcp`.)

The keystone is `muster.oauth.server.resourceIdentifier`, set in shared-configs
to `agentgateway-host/mcp`. It makes muster advertise the **agentgateway**
resource in its own OAuth metadata, so discovery is consistent regardless of
which hostname the client actually reached muster through.

```mermaid
sequenceDiagram
    autonumber
    participant C as MCP client
    participant A as agentgateway /mcp
    participant M as muster

    C->>A: GET /mcp (no token)
    A->>M: forward
    M-->>A: 401 WWW-Authenticate: Bearer<br/>resource_metadata=muster-host/.well-known/oauth-protected-resource
    A-->>C: 401 (header preserved by route-scoped BTP)

    C->>M: GET /.well-known/oauth-protected-resource
    M-->>C: resource = agentgateway-host/mcp  ← matches the URL dialled

    C->>A: GET /.well-known/oauth-authorization-server
    A->>M: proxied (standard HTTPRoute, agentic-platform-mcps)
    M-->>C: auth-server metadata (DCR endpoint, token endpoint, …)

    C->>M: DCR / CIMD directly at muster-host
    M-->>C: client credentials

    C->>A: GET /mcp + Bearer token
    A->>M: forward token
    M-->>C: 200 — tools served
```

Notes:

- muster's OAuth endpoints (`/.well-known/*`, DCR, token) remain publicly
  reachable on `muster-host`. agentgateway only proxies `/mcp` — Gateway API
  path-specificity (`/mcp` beats `/`) keeps every other path on muster directly.
- Step 5 (`oauth-authorization-server` via agentgateway) is the proxy route
  added by [agentic-platform-mcps](https://github.com/giantswarm/agentic-platform-mcps),
  so the client can do the whole flow against the single agentgateway hostname.

---

## 3. Token handling at muster

Once a valid token reaches muster, muster aggregates many downstream MCP servers
behind one endpoint. Each server entry declares **how** its token is obtained.
This is per-server config in the `agentic-platform-mcps` `mcpServers` list, not a
gateway concern.

```mermaid
flowchart TD
    in["inbound Dex token<br/>(validated by muster)"]

    in --> mode{"per-server<br/>auth.mode"}

    mode -->|forward| fwd["token forwarded as-is"]
    mode -->|exchange| exch["RFC 8693 token exchange<br/>via the spoke's Dex<br/>(identityProviders ref)"]

    fwd --> same["same-cluster MCP server<br/>e.g. mcp-kubernetes on this cluster<br/>caller's Dex token already valid"]
    exch --> remote["remote / spoke MCP server<br/>e.g. mcp-kubernetes on a spoke cluster<br/>needs a cluster-specific token"]
```

| `auth.mode` | When | Mechanism |
|---|---|---|
| `forward` | Downstream server trusts the **same** issuer the caller authenticated with (typically same-cluster). | muster passes the inbound bearer token through unchanged. No exchange. |
| `exchange` | Downstream server lives behind a **different** issuer (a spoke/remote cluster). | muster performs an [RFC 8693](https://www.rfc-editor.org/rfc/rfc8693) token exchange against the spoke's Dex `tokenEndpoint`, using credentials from the `identityProviders.<provider>` entry, to mint a token the downstream server accepts. |

Example (`exchange` against a spoke cluster's Dex):

```yaml
agentic-platform-mcps:
  mcpServers:
    - cluster: <spoke>
      group: kubernetes
      url: https://mcp-kubernetes.<spoke>.<base>/mcp
      auth:
        mode: exchange
        provider: <spoke>          # ref into identityProviders
  identityProviders:
    <spoke>:
      tokenEndpoint: https://dex.<spoke>.<base>/token
      connectorId: giantswarm-simple-oidc
      credentialsSecret:
        name: <spoke>-token-exchange-credentials
        clientIdKey: client-id
        clientSecretKey: client-secret
```

### On-behalf-of (OBO): local mint + human impersonation

A kagent agent reaching a downstream server forwards the human's muster token as
`Authorization` and its own ServiceAccount token as `X-Actor-Token`. muster
validates both and **local-mints** (`auth.mode: localMint`, `enableJWTMode: true`) a
token for the downstream audience carrying the human as `sub` and the agent SA in
the RFC 8693 `act` claim. The downstream server (e.g. mcp-kubernetes) cannot present
that token to the kube-apiserver as a bearer (wrong issuer/audience), so it
authenticates with its own SA token and sets `Impersonate-User` to the human plus
`Impersonate-Extra-actor` to the agent SA. Kubernetes RBAC and the audit log then
reflect the human, with the acting agent recorded.

A trusted-issuer token with no `act` claim is rejected: only on-behalf-of is
accepted, and any cryptographically validated actor is allowed (the impersonated
human's downstream RBAC governs access). The impersonation `ClusterRole` is rendered
by the mcp-kubernetes chart (`*-obo-impersonate`), not by agentic-platform.

---

## 4. Edge JWT validation and JWKS

This section applies only to the `agentgateway-*` modes (in `muster-direct` mode
there is no agentgateway and muster is the sole validator). By default
agentgateway runs `auth.passthrough`: it forwards the token to muster
without inspecting it, and muster is the only validator. Optionally, agentgateway
can validate the JWT **at the edge** (`oauthMode: validate`) as a first layer —
muster still validates downstream as a second layer. Edge JWT validation is the
relevant model for `agentgateway-direct`, where agentgateway must gate traffic
on its own. Token exchange (§3) is
unaffected: agentgateway only ever sees the inbound token; muster's internal
RFC 8693 exchanges happen behind it.

### Why muster signs its own tokens now

Before agentgateway, muster was the **only** enforcement point: it ran the OAuth
server (DCR/CIMD), held the session state, and validated every request itself. A
token only had to mean something *to muster*, so an opaque session reference was
enough — nothing else ever needed to read it.

agentgateway changes that. It is now an **independent** enforcement and
observability layer sitting in front of muster, and edge validation
(`oauthMode: validate`) means agentgateway must decide *on its own* whether a
token is valid — without a round-trip back to muster on every request. That only
works if the token is a **self-contained, signed JWT** whose signature
agentgateway can verify statelessly against a published key set. An opaque
session token is unverifiable by anyone but muster, so it can't gate a second,
independent component.

So muster takes on an issuer role it did not have before (`enableJWTMode: true`):

- **Signs its own JWTs** (`iss=muster`) with the `jwt-signing-key` (EC P-256),
  instead of handing out opaque session tokens.
- **Publishes `/.well-known/jwks.json`** so agentgateway can fetch the public key
  and verify signatures at the edge.
- **Audience-binds** each token to `resourceIdentifier` (`agentgateway-host/mcp`),
  so a token minted for this platform cannot be replayed at an unrelated
  resource — agentgateway checks that `aud` matches the hostname the client
  actually dialled.

This is additive, not a replacement: muster still validates downstream as the
second layer (and token exchange in §3 is untouched). The signed-JWT capability
exists purely so a *second*, independent component can trust the token without
asking muster.

Edge validation needs a JWKS to verify token signatures. There are two
topologies, and they differ in whether the JWKS NetworkPolicy egress rule is
required.

```mermaid
flowchart TD
    subgraph A["A · muster JWT mode (default for edge validation)"]
        a_agw["agentgateway :8080<br/>oauthMode: validate"]
        a_m["muster :8090<br/>enableJWTMode: true<br/>signs own JWTs (iss=muster)<br/>serves /.well-known/jwks.json"]
        a_agw -->|"jwksBackendRef → agentic-platform-muster:8090<br/>SAME namespace, port 8090"| a_m
        a_note["existing muster egress rule already covers it<br/>→ gateway.jwksEgress NOT needed"]
    end

    subgraph B["B · external JWKS (e.g. Dex)"]
        b_agw["agentgateway :8080<br/>oauthMode: validate"]
        b_dex["external IdP / Dex<br/>JWKS on a non-standard port<br/>e.g. :5556 in another namespace"]
        b_agw -->|"cross-namespace, non-80/443 port"| b_dex
        b_note["needs gateway.jwksEgress.enabled: true<br/>→ adds the data-plane egress rule"]
    end
```

### When `gateway.jwksEgress` is required

`gateway.jwksEgress` is an `agentgateway-*` data-plane knob (most relevant to
`agentgateway-direct`, where agentgateway validates JWTs at the edge against an
external key set).

The data-plane NetworkPolicy
(`networkpolicy-dataplane-{cilium,kubernetes}.yaml`) allows the proxy egress to
muster:8090 and the agentgateway controller:9978 by default. Fetching JWKS from
anywhere else is blocked unless you open it explicitly:

- **Topology A — muster JWT mode:** JWKS is muster's own `/.well-known/jwks.json`
  on `:8090` in the **same** namespace. The existing muster egress rule already
  permits it, so **leave `gateway.jwksEgress.enabled: false`**. No
  `ReferenceGrant` needed either (same namespace).
- **Topology B — external JWKS:** the JWKS service (typically Dex on `:5556`)
  runs in another namespace on a port the default cluster egress rules
  (80/443) don't cover. Enable the rule:

  ```yaml
  gateway:
    jwksEgress:
      enabled: true
      namespace: giantswarm     # where the JWKS service lives
      port: 5556                # Dex's JWKS port
      podSelector: {}           # optional: narrow beyond namespace
  ```

### Enabling edge validation (Topology A)

1. Add a `jwt-signing-key` (EC P-256 PEM) to the cluster's
   `agentic-platform-secrets`.
2. `enableJWTMode: true` on muster — it signs its own JWTs (`iss=muster`),
   exposes `/.well-known/jwks.json`, and audience-binds tokens to
   `resourceIdentifier` (`agentgateway-host/mcp`).
3. `oauthMode: validate` with `jwt.jwksBackendRef → agentic-platform-muster:8090`
   (set in shared-configs).

> Requires the muster build that loads the signing key from file and guards the
> `jwtSigningKeyFile` chart template — without it, `enableJWTMode: true` crashes
> muster at startup. Track the `muster` dependency version in `Chart.yaml`.
