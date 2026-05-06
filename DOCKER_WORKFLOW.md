# OpenWebUI Docker Workflow

Use these commands to rebuild and run your customized fork safely.

## 1. Clean Up "Ghost" Space
Run this whenever you feel your disk is getting full. It safely removes old builds and stopped containers.
```bash
sudo docker system prune -f
```

## 2. Build the App
This command builds your customized code from scratch for ARM64 architecture.
```bash
sudo docker build --no-cache --platform linux/arm64 -t open-webui .
```

## 3. Run the App
This command stops the old version and starts the new one.
```bash
sudo docker rm -f open-webui; sudo docker run -it -p 3000:8080 --network ai_default --env-file .env -v open-webui-data:/app/backend/data --name open-webui open-webui
```

---

### Automated "All-in-One" Command
If you want to do everything in one go (Build, then Run, then Clean up the mess):
```bash
sudo docker build --no-cache --platform linux/arm64 -t open-webui . && \
sudo docker rm -f open-webui; \
sudo docker run -it -p 3000:8080 --network ai_default --env-file .env -v open-webui-data:/app/backend/data --name open-webui open-webui && \
sudo docker image prune -f
```
