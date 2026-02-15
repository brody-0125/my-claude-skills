# SE Authorization Cluster Reference

> Reference material for agents Z-1, Z-2, Z-3, Z-4

## Table of Contents

| Section | Agent | Line Range |
|---------|-------|------------|
| Access Control Models | z1-access-model-selector | 20-130 |
| Policy Engine Patterns | z2-policy-designer | 131-230 |
| Permission Audit Patterns | z3-permission-auditor | 231-310 |
| Scope Design Patterns | z4-scope-architect | 311-400 |

---

<!-- SECTION:z1-access-model-selector:START -->
## 1. Access Control Models

### ACL (Access Control List)

The simplest model. Each resource maintains a list of (subject, permission) pairs.

```sql
CREATE TABLE resource_acl (
    resource_id   UUID NOT NULL,
    resource_type VARCHAR(50) NOT NULL,
    subject_id    UUID NOT NULL,
    subject_type  VARCHAR(20) NOT NULL,  -- 'user' | 'group' | 'service'
    permission    VARCHAR(20) NOT NULL,  -- 'read' | 'write' | 'delete' | 'admin'
    granted_at    TIMESTAMP DEFAULT NOW(),
    granted_by    UUID NOT NULL,
    PRIMARY KEY (resource_id, subject_id, permission)
);

-- Check access
SELECT 1 FROM resource_acl
WHERE resource_id = :resource_id
  AND subject_id IN (:user_id, :user_group_ids)
  AND permission = :required_permission;
```

Best for: simple applications with direct user-to-resource mapping (file systems, shared documents). Breaks down when the number of resources * users grows large.

### RBAC (Role-Based Access Control)

Users are assigned roles; roles contain permissions. Reduces management complexity from O(users * resources) to O(roles * resources).

**Role hierarchy:**

```
super_admin
  └── admin
       ├── user_manager
       │    ├── user_viewer
       │    └── user_editor
       ├── content_manager
       │    ├── content_viewer
       │    └── content_editor
       └── billing_manager
            ├── billing_viewer
            └── billing_editor
```

**Database schema:**

```sql
CREATE TABLE roles (
    id          UUID PRIMARY KEY,
    name        VARCHAR(100) UNIQUE NOT NULL,
    parent_id   UUID REFERENCES roles(id),  -- hierarchy
    description TEXT,
    is_system   BOOLEAN DEFAULT FALSE       -- prevent deletion
);

CREATE TABLE permissions (
    id          UUID PRIMARY KEY,
    resource    VARCHAR(100) NOT NULL,       -- e.g., 'users', 'orders'
    action      VARCHAR(50) NOT NULL,        -- e.g., 'read', 'write', 'delete'
    UNIQUE (resource, action)
);

CREATE TABLE role_permissions (
    role_id       UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id    UUID NOT NULL,
    role_id    UUID REFERENCES roles(id) ON DELETE CASCADE,
    scope      VARCHAR(100),                -- optional: 'org:acme', 'team:eng'
    granted_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,                   -- time-bound role assignment
    PRIMARY KEY (user_id, role_id, COALESCE(scope, ''))
);
```

**Spring Security implementation:**

```java
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests(auth -> auth
            .requestMatchers("/api/admin/**").hasRole("ADMIN")
            .requestMatchers("/api/users/**").hasAnyRole("USER_MANAGER", "ADMIN")
            .requestMatchers("/api/public/**").permitAll()
            .anyRequest().authenticated()
        );
        return http.build();
    }
}

@RestController
@RequestMapping("/api/users")
public class UserController {

    @GetMapping
    @Secured("ROLE_USER_VIEWER")
    public List<UserDto> listUsers() { /* ... */ }

    @PostMapping
    @RolesAllowed({"ROLE_USER_MANAGER", "ROLE_ADMIN"})
    public UserDto createUser(@RequestBody CreateUserRequest req) { /* ... */ }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN') and #id != authentication.principal.id")
    public void deleteUser(@PathVariable UUID id) { /* ... */ }
}
```

### ABAC (Attribute-Based Access Control)

Decisions based on attributes of the subject, resource, action, and environment.

**Policy structure:**

```
Decision = f(Subject Attributes, Resource Attributes, Action, Environment)

Subject Attributes:   role, department, clearance_level, location
Resource Attributes:  classification, owner, department, sensitivity
Action:               read, write, delete, approve
Environment:          time_of_day, ip_range, device_type, risk_score
```

**XACML-style policy (simplified):**

```xml
<Policy PolicyId="doc-access" RuleCombiningAlgId="deny-overrides">
  <Target>
    <Resource>urn:example:document</Resource>
  </Target>

  <Rule RuleId="allow-same-dept" Effect="Permit">
    <Condition>
      <Apply FunctionId="string-equal">
        <SubjectAttributeDesignator AttributeId="department"/>
        <ResourceAttributeDesignator AttributeId="department"/>
      </Apply>
      <Apply FunctionId="string-at-least-one-member-of">
        <SubjectAttributeDesignator AttributeId="role"/>
        <AttributeValue>analyst</AttributeValue>
        <AttributeValue>manager</AttributeValue>
      </Apply>
    </Condition>
  </Rule>

  <Rule RuleId="deny-outside-hours" Effect="Deny">
    <Condition>
      <Apply FunctionId="time-not-in-range">
        <EnvironmentAttributeDesignator AttributeId="current-time"/>
        <AttributeValue>08:00:00</AttributeValue>
        <AttributeValue>20:00:00</AttributeValue>
      </Apply>
    </Condition>
  </Rule>
</Policy>
```

**Spring ABAC with SpEL expressions:**

```java
@PreAuthorize(
    "@abacService.evaluate(" +
    "  authentication.principal, " +      // subject
    "  #document, " +                      // resource
    "  'read', " +                         // action
    "  T(java.time.LocalTime).now()" +     // environment
    ")"
)
public Document getDocument(@PathVariable UUID id) {
    Document document = documentRepository.findById(id).orElseThrow();
    return document;
}

@Service
public class AbacService {
    public boolean evaluate(UserPrincipal subject, Document resource,
                            String action, LocalTime currentTime) {
        // Same department check
        if (!subject.getDepartment().equals(resource.getDepartment())) {
            return false;
        }
        // Business hours check for sensitive documents
        if (resource.getSensitivity() == Sensitivity.HIGH) {
            if (currentTime.isBefore(LocalTime.of(8, 0))
                || currentTime.isAfter(LocalTime.of(20, 0))) {
                return false;
            }
        }
        // Clearance level check
        return subject.getClearanceLevel() >= resource.getRequiredClearance();
    }
}
```

### ReBAC (Relationship-Based Access Control)

Access is determined by the relationship graph between subjects and resources. Inspired by Google's Zanzibar paper (2019).

**Tuple-based relationships:**

```
// Format: object#relation@subject
document:readme#viewer@user:alice
document:readme#editor@user:bob
document:readme#parent@folder:engineering
folder:engineering#viewer@group:eng-team#member
group:eng-team#member@user:alice
group:eng-team#member@user:charlie
organization:acme#admin@user:dave

// Check: Can alice view document:readme?
// Path 1: document:readme#viewer@user:alice            (direct tuple)
// Path 2: document:readme#parent@folder:engineering
//         folder:engineering#viewer@group:eng-team#member
//         group:eng-team#member@user:alice               (indirect via group)
// Result: ALLOWED
```

**SpiceDB schema definition:**

```zed
definition user {}

definition group {
    relation member: user | group#member
    relation admin: user

    permission manage = admin
    permission membership = member + admin
}

definition folder {
    relation owner: user
    relation viewer: user | group#member
    relation parent: folder

    permission view = viewer + owner + parent->view
    permission edit = owner + parent->edit
}

definition document {
    relation owner: user
    relation editor: user | group#member
    relation viewer: user | group#member
    relation parent: folder

    permission view = viewer + editor + owner + parent->view
    permission edit = editor + owner + parent->edit
    permission delete = owner
}
```

**OpenFGA authorization model (JSON):**

```json
{
  "schema_version": "1.1",
  "type_definitions": [
    {
      "type": "document",
      "relations": {
        "owner": { "this": {} },
        "editor": { "this": {} },
        "viewer": {
          "union": {
            "child": [
              { "this": {} },
              { "computedUserset": { "relation": "editor" } },
              { "tupleToUserset": {
                  "tupleset": { "relation": "parent" },
                  "computedUserset": { "relation": "viewer" }
              }}
            ]
          }
        },
        "parent": { "this": {} }
      }
    }
  ]
}
```

### Model Decision Matrix

| Criteria | ACL | RBAC | ABAC | ReBAC |
|----------|-----|------|------|-------|
| Best for | Simple file sharing | Enterprise apps | Context-aware access | Social/org hierarchies |
| Complexity | Low | Medium | High | High |
| Scalability | Poor (N*M) | Good | Good | Excellent |
| Granularity | Per-resource | Per-role | Per-attribute combo | Per-relationship |
| Dynamic context | No | No | Yes | Partial |
| Audit trail | Simple | Role-based | Policy-based | Graph-based |
| Implementation | DIY | Spring Security, etc. | OPA, custom | SpiceDB, OpenFGA |
| When to avoid | >100 resources | >50 roles (explosion) | Simple static perms | No relationships |
<!-- SECTION:z1-access-model-selector:END -->

---

<!-- SECTION:z2-policy-designer:START -->
## 2. Policy Engine Patterns

### OPA (Open Policy Agent) with Rego

**Architecture:** OPA runs as a sidecar or standalone service. Applications query OPA for policy decisions via REST API or Go library.

```
Application  --(query)--> OPA  --(evaluates)--> Policy (Rego)
                                                   + Data (JSON)
                            |
                       Decision (allow/deny + details)
```

**Rego policy example (API authorization):**

```rego
package authz

import rego.v1

default allow := false

# Allow admins to do anything
allow if {
    input.user.roles[_] == "admin"
}

# Allow users to read their own data
allow if {
    input.method == "GET"
    input.path == ["api", "users", input.user.id]
}

# Allow managers to read team member data
allow if {
    input.method == "GET"
    input.path = ["api", "users", user_id]
    some user_id
    team_member(input.user.id, user_id)
}

team_member(manager_id, member_id) if {
    data.teams[team_name].manager == manager_id
    data.teams[team_name].members[_] == member_id
}

# Rate-limited endpoint access
allow if {
    input.path[0] == "api"
    input.path[1] == "search"
    count(data.rate_limits[input.user.id].requests) < 100
}

# Return detailed decision with reasons
decision := {
    "allow": allow,
    "reasons": reasons,
    "required_mfa": requires_mfa
}

reasons contains "admin_role" if {
    input.user.roles[_] == "admin"
}

requires_mfa if {
    input.path[1] == "admin"
    not input.user.mfa_verified
}
```

**OPA data loading and bundle API:**

```yaml
# OPA configuration (opa.yaml)
services:
  policy-server:
    url: https://policy-bundles.example.com
    credentials:
      bearer:
        token: ${POLICY_TOKEN}

bundles:
  authz:
    service: policy-server
    resource: /bundles/authz.tar.gz
    polling:
      min_delay_seconds: 30
      max_delay_seconds: 120

decision_logs:
  service: policy-server
  reporting:
    min_delay_seconds: 5
    max_delay_seconds: 30
```

**Performance tuning:**
- Use `partial evaluation` for frequently checked policies
- Index policies on `input.path` or `input.method` for fast lookup
- Keep data documents under 1MB per bundle for fast loading
- Use `print()` for debugging, remove in production
- Benchmark with `opa bench` before deployment

### Cedar (AWS Verified Permissions)

**Cedar policy syntax:**

```cedar
// Allow editors to update any document in their department
permit (
    principal in Role::"editor",
    action in [Action::"update", Action::"read"],
    resource in Department::"engineering"
) when {
    principal.department == resource.department &&
    context.ip_address.isInRange(ip("10.0.0.0/8"))
};

// Forbid deleting documents marked as legal hold
forbid (
    principal,
    action == Action::"delete",
    resource
) when {
    resource.legal_hold == true
} unless {
    principal in Role::"legal_admin"
};

// Time-based access control
permit (
    principal,
    action == Action::"read",
    resource in ResourceType::"financial_report"
) when {
    context.time.hour >= 9 && context.time.hour <= 17 &&
    principal.clearance_level >= resource.required_clearance
};
```

**Cedar entity types and action definitions:**

```cedar
// Entity schema
entity User in [Group, Role] = {
    department: String,
    clearance_level: Long,
    email: String
};

entity Document in [Folder] = {
    owner: User,
    department: String,
    classification: String,
    legal_hold: Bool,
    required_clearance: Long
};

entity Folder in [Folder];

// Action declarations
action read, update, delete, share appliesTo {
    principal: [User, Group],
    resource: [Document, Folder]
};
```

### Casbin

**Model definition (RBAC with domain/tenant):**

```ini
# model.conf
[request_definition]
r = sub, dom, obj, act

[policy_definition]
p = sub, dom, obj, act

[role_definition]
g = _, _, _    # user, role, domain

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = g(r.sub, p.sub, r.dom) && r.dom == p.dom && r.obj == p.obj && r.act == p.act
```

**Policy storage (CSV or database adapter):**

```csv
p, admin, tenant1, /api/users, GET
p, admin, tenant1, /api/users, POST
p, admin, tenant1, /api/users/*, DELETE
p, editor, tenant1, /api/articles, GET
p, editor, tenant1, /api/articles, POST

g, alice, admin, tenant1
g, bob, editor, tenant1
g, charlie, admin, tenant2
```

**Casbin adapter patterns:**

```go
import (
    "github.com/casbin/casbin/v2"
    gormadapter "github.com/casbin/gorm-adapter/v3"
)

func NewEnforcer(dsn string) (*casbin.Enforcer, error) {
    adapter, err := gormadapter.NewAdapter("postgres", dsn, true)
    if err != nil {
        return nil, err
    }

    enforcer, err := casbin.NewEnforcer("model.conf", adapter)
    if err != nil {
        return nil, err
    }

    // Auto-reload policies every 60 seconds
    enforcer.EnableAutoLoadPolicy(60 * time.Second)

    return enforcer, nil
}

// Usage
func CheckPermission(e *casbin.Enforcer, user, tenant, resource, action string) bool {
    ok, err := e.Enforce(user, tenant, resource, action)
    if err != nil {
        log.Error("Policy evaluation error", "error", err)
        return false  // Fail closed
    }
    return ok
}
```

### PEP/PDP/PIP/PAP Architecture

```
                    ┌─────────────────────┐
                    │   PAP               │
                    │ (Policy Admin Point) │
                    │ UI for policy mgmt  │
                    └─────────┬───────────┘
                              │ policy CRUD
                              ▼
┌──────────┐  request  ┌─────────────┐  fetch   ┌─────────────┐
│   PEP    │──────────>│    PDP      │────────-->│    PIP       │
│ (Enforce)│           │  (Decision) │           │ (Info Lookup)│
│          │<──────────│             │<──────────│              │
│ API GW / │  allow/   │ OPA/Cedar/  │  attrs   │ LDAP/DB/API  │
│ Middleware│  deny    │ Custom      │          │ User attrs   │
└──────────┘           └─────────────┘          └──────────────┘
```

**PEP placement options:**

| Location | Pros | Cons | Best For |
|----------|------|------|----------|
| API Gateway | Centralized, consistent | Coarse-grained only | URL/method-level |
| Middleware | Per-service, flexible | Repeated implementation | Service-level |
| Method/annotation | Fine-grained | Tightly coupled to code | Business logic |
| Database (RLS) | Data-level security | DB-specific, limited logic | Multi-tenant data |

**Spring Boot middleware PEP example:**

```java
@Component
public class PolicyEnforcementFilter extends OncePerRequestFilter {

    private final OpaClient opaClient;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                     HttpServletResponse response,
                                     FilterChain filterChain)
            throws ServletException, IOException {

        AuthzRequest authzReq = AuthzRequest.builder()
            .method(request.getMethod())
            .path(request.getRequestURI())
            .user(SecurityContextHolder.getContext().getAuthentication())
            .clientIp(request.getRemoteAddr())
            .timestamp(Instant.now())
            .build();

        AuthzDecision decision = opaClient.evaluate(authzReq);

        if (!decision.isAllowed()) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.getWriter().write(
                "{\"error\":\"forbidden\",\"reason\":\"" + decision.getReason() + "\"}"
            );
            return;
        }

        // Attach decision metadata for downstream use
        request.setAttribute("authz.scopes", decision.getGrantedScopes());
        filterChain.doFilter(request, response);
    }
}
```
<!-- SECTION:z2-policy-designer:END -->

---

<!-- SECTION:z3-permission-auditor:START -->
## 3. Permission Audit Patterns

### Least-Privilege Checklist

```
[ ] Every service account has documented purpose and owner
[ ] No user has permanent admin/superuser access (use JIT elevation)
[ ] API keys are scoped to minimum required permissions
[ ] Database users have table/column-level grants (not db-wide)
[ ] Cloud IAM roles are custom (not using built-in admin roles)
[ ] Service mesh restricts inter-service communication (not allow-all)
[ ] CI/CD pipelines use short-lived credentials (OIDC federation)
[ ] Third-party integrations use OAuth scopes (not API keys)
[ ] Default deny policy is in place (explicit allow required)
[ ] Unused permissions are automatically flagged after 90 days
```

### Over-Privilege Detection Queries

```sql
-- Users with admin role who haven't performed admin actions in 90 days
SELECT ur.user_id, u.email, ur.granted_at
FROM user_roles ur
JOIN users u ON ur.user_id = u.id
JOIN roles r ON ur.role_id = r.id
WHERE r.name = 'admin'
  AND ur.user_id NOT IN (
    SELECT DISTINCT user_id FROM audit_log
    WHERE action IN ('user.create', 'user.delete', 'config.update', 'role.assign')
      AND created_at > NOW() - INTERVAL '90 days'
  );

-- Roles with permissions that are never exercised
SELECT r.name AS role_name, p.resource, p.action,
       COUNT(al.id) AS usage_count
FROM role_permissions rp
JOIN roles r ON rp.role_id = r.id
JOIN permissions p ON rp.permission_id = p.id
LEFT JOIN audit_log al ON al.action = CONCAT(p.resource, '.', p.action)
  AND al.created_at > NOW() - INTERVAL '90 days'
GROUP BY r.name, p.resource, p.action
HAVING COUNT(al.id) = 0
ORDER BY r.name;

-- Users with multiple conflicting roles (separation of duties violation)
SELECT u.email,
       array_agg(r.name) AS roles
FROM user_roles ur
JOIN users u ON ur.user_id = u.id
JOIN roles r ON ur.role_id = r.id
WHERE r.name IN ('finance_approver', 'finance_requester')  -- SoD conflict pair
GROUP BY u.email
HAVING COUNT(DISTINCT r.name) > 1;
```

### Role Explosion Metrics

```
Healthy:     #roles < #users * 0.5
Warning:     #roles >= #users * 0.5 AND < #users * 1.0
Critical:    #roles >= #users (role explosion)

Additional signals:
  - Average permissions per role < 5: healthy
  - Average permissions per role 5-15: review needed
  - Average permissions per role > 15: decompose roles
  - Single-user roles > 10% of total roles: consider ABAC migration
  - Role inheritance depth > 4: flatten hierarchy
```

**Automated role explosion detection:**

```python
async def detect_role_explosion(db) -> AuditReport:
    stats = await db.fetchrow("""
        SELECT
            (SELECT COUNT(*) FROM roles) AS role_count,
            (SELECT COUNT(*) FROM users WHERE active = true) AS user_count,
            (SELECT AVG(perm_count) FROM (
                SELECT COUNT(*) AS perm_count FROM role_permissions GROUP BY role_id
            ) AS t) AS avg_perms_per_role,
            (SELECT COUNT(*) FROM roles WHERE id IN (
                SELECT role_id FROM user_roles GROUP BY role_id HAVING COUNT(*) = 1
            )) AS single_user_roles
    """)

    findings = []
    ratio = stats['role_count'] / max(stats['user_count'], 1)

    if ratio >= 1.0:
        findings.append(Finding(
            severity="CRITICAL",
            message=f"Role explosion: {stats['role_count']} roles for {stats['user_count']} users (ratio: {ratio:.1f}x)",
            recommendation="Migrate to ABAC or ReBAC for dynamic access control"
        ))

    if stats['avg_perms_per_role'] > 15:
        findings.append(Finding(
            severity="WARNING",
            message=f"Overly broad roles: avg {stats['avg_perms_per_role']:.0f} permissions per role",
            recommendation="Decompose into smaller, focused roles"
        ))

    if stats['single_user_roles'] > stats['role_count'] * 0.1:
        findings.append(Finding(
            severity="WARNING",
            message=f"{stats['single_user_roles']} single-user roles ({stats['single_user_roles']/stats['role_count']*100:.0f}%)",
            recommendation="Use ABAC for user-specific policies instead of single-user roles"
        ))

    return AuditReport(findings=findings, stats=stats)
```

### Permission Matrix Template

```
Resource      | viewer | editor | manager | admin | auditor
──────────────|--------|--------|---------|-------|--------
users.list    |   R    |   R    |    R    |   R   |   R
users.detail  |   -    |   R    |    R    |   R   |   R
users.create  |   -    |   -    |    CW   |  CW   |   -
users.update  |   -    |   W*   |    W    |   W   |   -
users.delete  |   -    |   -    |    -    |   D   |   -
orders.list   |   R    |   R    |    R    |   R   |   R
orders.export |   -    |   -    |    R    |   R   |   R
audit.view    |   -    |   -    |    -    |   R   |   R
config.update |   -    |   -    |    -    |   W   |   -

Legend: R=Read, W=Write, C=Create, D=Delete, *=own records only
```

### Access Review Workflow

```
1. TRIGGER: Quarterly automated access review initiation
   - System generates review tasks for each manager
   - Include: user list, current roles, last activity dates

2. REVIEW: Manager reviews each direct report's access
   - Approve: access confirmed as needed
   - Modify: reduce scope or change role
   - Revoke: remove access entirely
   - Escalate: flag for security team review

3. ATTEST: Manager signs off on review completion
   - Deadline: 14 days from initiation
   - Escalation: unreviewed access auto-flagged at day 7
   - Non-completion: escalate to director + CISO at day 14

4. ENFORCE: System applies approved changes
   - Revocations applied immediately
   - Modifications applied with 24h grace period (revert window)
   - Audit log entry for every decision

5. REPORT: Compliance report generated
   - Coverage: % of users reviewed
   - Changes: # of revocations, modifications
   - Exceptions: users not reviewed, overdue reviews
```
<!-- SECTION:z3-permission-auditor:END -->

---

<!-- SECTION:z4-scope-architect:START -->
## 4. Scope Design Patterns

### Resource-Based Scopes

```
Format: <action>:<resource>[:<sub-resource>]

Examples:
  read:users                  # Read user list and profiles
  write:users                 # Create and update users
  delete:users                # Delete users
  read:users:email            # Read only user email addresses
  write:orders                # Create and update orders
  read:orders:history         # Read order history only
  admin:billing               # Full billing management
  read:analytics:dashboard    # View analytics dashboards
```

**Scope registration (OpenAPI/Swagger integration):**

```yaml
# openapi.yaml
components:
  securitySchemes:
    oauth2:
      type: oauth2
      flows:
        authorizationCode:
          authorizationUrl: https://auth.example.com/authorize
          tokenUrl: https://auth.example.com/token
          scopes:
            read:users: "Read user profiles"
            write:users: "Create and update users"
            delete:users: "Delete user accounts"
            read:orders: "Read order information"
            write:orders: "Create and update orders"
            admin:billing: "Manage billing and subscriptions"

paths:
  /api/users:
    get:
      security:
        - oauth2: [read:users]
    post:
      security:
        - oauth2: [write:users]
  /api/users/{id}:
    delete:
      security:
        - oauth2: [delete:users]
```

### Hierarchical Scopes

```
Scope hierarchy (parent grants all children):

  admin                         # Full access to everything
  ├── admin:users               # Full user management
  │   ├── read:users            # Read users
  │   ├── write:users           # Write users
  │   └── delete:users          # Delete users
  ├── admin:orders              # Full order management
  │   ├── read:orders
  │   ├── write:orders
  │   └── delete:orders
  └── admin:billing
      ├── read:billing
      └── write:billing
```

**Scope resolution function:**

```python
SCOPE_HIERARCHY = {
    "admin": ["admin:users", "admin:orders", "admin:billing"],
    "admin:users": ["read:users", "write:users", "delete:users"],
    "admin:orders": ["read:orders", "write:orders", "delete:orders"],
    "admin:billing": ["read:billing", "write:billing"],
}

def resolve_scopes(granted_scopes: set[str]) -> set[str]:
    """Expand hierarchical scopes to their full set of effective scopes."""
    resolved = set()
    queue = list(granted_scopes)

    while queue:
        scope = queue.pop()
        if scope not in resolved:
            resolved.add(scope)
            children = SCOPE_HIERARCHY.get(scope, [])
            queue.extend(children)

    return resolved

# Example:
# resolve_scopes({"admin:users"})
# => {"admin:users", "read:users", "write:users", "delete:users"}
```

### Dynamic Scope Narrowing

When a client requests more scopes than it needs, the authorization server can narrow the granted scopes based on context.

```python
def narrow_scopes(requested_scopes: set[str],
                  client_allowed_scopes: set[str],
                  user_permissions: set[str],
                  risk_context: RiskContext) -> set[str]:
    """
    Narrow scopes based on:
    1. Client registration (max allowed scopes)
    2. User's actual permissions
    3. Runtime risk assessment
    """
    # Step 1: Intersect with client's registered scopes
    narrowed = requested_scopes & client_allowed_scopes

    # Step 2: Intersect with user's permissions
    narrowed = narrowed & user_permissions

    # Step 3: Risk-based narrowing
    if risk_context.score > 0.7:  # High risk
        # Remove write/delete scopes for high-risk sessions
        narrowed = {s for s in narrowed if not s.startswith(('write:', 'delete:'))}

    if risk_context.new_device:
        # First-time device: read-only for first session
        narrowed = {s for s in narrowed if s.startswith('read:')}

    return narrowed
```

### Consent Management Flow

```
User                Client App              Auth Server            Consent DB
 |                      |                        |                      |
 | 1. Login/Auth        |                        |                      |
 |--------------------->|-- /authorize ---------->|                      |
 |                      |  scopes: read:profile   |                      |
 |                      |          write:orders    |                      |
 |                      |          read:billing    |                      |
 |                      |                        |                      |
 |                      |                        |-- check existing ---->|
 |                      |                        |<-- partial consent ---|
 |                      |                        |   (read:profile      |
 |                      |                        |    already granted)   |
 |                      |                        |                      |
 |<-- Consent screen ---|-- show only NEW -------|                      |
 |    "App requests:"   |   scopes:              |                      |
 |    [x] write:orders  |   write:orders         |                      |
 |    [x] read:billing  |   read:billing         |                      |
 |                      |                        |                      |
 |-- Approve (partial)->|-- consent response ---->|                      |
 |   (only write:orders)|                        |-- store consent ---->|
 |                      |                        |   write:orders       |
 |                      |                        |                      |
 |                      |<-- token with scopes --|                      |
 |                      |   read:profile (prior) |                      |
 |                      |   write:orders (new)   |                      |
 |                      |   (read:billing denied) |                      |
```

### Token-Permission Mapping Strategies

**Strategy 1: Scopes embedded in token (stateless)**

```json
{
  "sub": "user-123",
  "scope": "read:users write:orders",
  "aud": "api.example.com",
  "exp": 1700000000
}
```

Pros: No additional lookup needed. Cons: Token grows with permissions, stale until expiry.

**Strategy 2: Scopes resolved at PEP (stateful)**

```json
{
  "sub": "user-123",
  "aud": "api.example.com",
  "exp": 1700000000
}
// PEP queries permission service: GET /permissions?user=user-123&resource=orders&action=write
```

Pros: Always current, fine-grained. Cons: Network latency, availability dependency.

**Strategy 3: Hybrid (scope categories in token, details resolved):**

```json
{
  "sub": "user-123",
  "scope_categories": ["users.read", "orders.full"],
  "perm_version": 42,
  "exp": 1700000000
}
// PEP caches permission details by perm_version
// Only re-fetches when version changes (event-driven invalidation)
```

Pros: Low latency (cached), reasonably current, manageable token size. Cons: Cache invalidation complexity.

**Scope enforcement middleware (Express.js):**

```javascript
function requireScopes(...requiredScopes) {
  return (req, res, next) => {
    const tokenScopes = new Set(req.auth.scope?.split(' ') || []);
    const resolvedScopes = resolveHierarchicalScopes(tokenScopes);

    const missing = requiredScopes.filter(s => !resolvedScopes.has(s));

    if (missing.length > 0) {
      return res.status(403).json({
        error: 'insufficient_scope',
        required: requiredScopes,
        missing: missing,
        hint: `Request additional scopes: ${missing.join(' ')}`
      });
    }

    // Attach effective scopes for downstream use
    req.effectiveScopes = resolvedScopes;
    next();
  };
}

// Usage
app.get('/api/users', requireScopes('read:users'), listUsers);
app.post('/api/orders', requireScopes('write:orders'), createOrder);
app.delete('/api/users/:id', requireScopes('delete:users'), deleteUser);
```
<!-- SECTION:z4-scope-architect:END -->
