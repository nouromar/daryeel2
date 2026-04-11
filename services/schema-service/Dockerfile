FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Keep the same directory structure as the repo so app/validation.py
# can locate Daryeel2/contracts via Path(__file__).resolve().parents[4].
WORKDIR /workspace/daryeel/Daryeel2/services/schema-service

# Install dependencies first (better layer caching).
COPY services/schema-service/requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir --upgrade pip \
 && python -m pip install --no-cache-dir --prefer-binary --retries 10 --timeout 120 -r requirements.txt

# Copy only what the service needs at runtime.
COPY services/schema-service/app ./app
COPY packages ../../packages
COPY apps/customer-app/contracts ../../apps/customer-app/contracts
COPY apps/customer-app/schemas ../../apps/customer-app/schemas

EXPOSE 8011

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8011"]
