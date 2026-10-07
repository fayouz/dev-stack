FROM python:3.13-alpine

RUN pip install --no-cache-dir inotify_simple==1.3.5

WORKDIR /app
COPY httpfile.py sync.py ./

# Fichiers des projets en lecture seule ; état (cookies de session, empreintes) dans /state
CMD ["python", "-u", "sync.py"]
