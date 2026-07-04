from fastapi import FastAPI

from voting.routers import health

# Initialize the main FastAPI application instance
app = FastAPI(title="voting")

# ####################
# routes
# ####################
# healthz/
app.include_router(health.router)
