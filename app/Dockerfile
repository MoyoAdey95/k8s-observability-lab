FROM python:3.12-slim

WORKDIR /srv

# created before the copy so the app files can be owned by it. The
# deployment's securityContext expects uid 1000.
RUN useradd --uid 1000 --no-create-home appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --chown matters. Without it the files arrive owned by root with
# whatever mode they carried on the build host, and a non-root user
# cannot read them.
COPY --chown=appuser:appuser . ./app/

USER appuser

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
