FROM python:3.12-slim
RUN pip install --no-cache-dir Pillow==11.3.0
WORKDIR /app
COPY worker.py /app/worker.py
USER 65532:65532
ENTRYPOINT ["python", "/app/worker.py"]
