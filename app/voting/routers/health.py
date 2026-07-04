from fastapi import APIRouter

# init router
router = APIRouter(tags=["health"])


# GET /healthz/
@router.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}
