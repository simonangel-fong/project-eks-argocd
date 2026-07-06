# project-eks-argocd

refactor - next stage
- istio abiemt
- package app with helm
  - istio
  - eso
  - albc
  - karpenter
- infra
  - file layouts

---

karpenter
gateway

Data: 
- uuid
---
app backend:
- GET /api/: {application: voting app,version:v0.2.0}

POLL
- GET /api/polls: list polls
- PUT /api/polls: create polls
- PATCH /api/polls/polls_id: update poll
- GET /api/polls/polls_id: query poll
- DEL /api/polls/polls_id: remove poll

VOTE:
- PUT /api/polls/polls_id/vote: create a vote; header
- GET /api/polls/polls_id/vote: create a vote; header

Tally:
- GET /api/polls/polls_id/vote: create a vote; header

