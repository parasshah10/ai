#!/bin/bash

set -e

# Configuration
IMAGE_NAME="open-webui"
CONTAINER_NAME="open-webui"
PLATFORM="linux/arm64"
PORT_MAPPING="3000:8080"
DATA_VOLUME="open-webui-data"
ENV_FILE=".env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Header
clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}       OpenWebUI Production Manager${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker is not installed"
    exit 1
fi

# Check container status
if sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if sudo docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        STATUS="${GREEN}Running${NC}"
        CONTAINER_EXISTS=true
        CONTAINER_RUNNING=true
    else
        STATUS="${YELLOW}Stopped${NC}"
        CONTAINER_EXISTS=true
        CONTAINER_RUNNING=false
    fi
else
    STATUS="${RED}Not created${NC}"
    CONTAINER_EXISTS=false
    CONTAINER_RUNNING=false
fi

# Check if image exists
if sudo docker images --format "{{.Repository}}" | grep -q "^${IMAGE_NAME}$"; then
    IMAGE_EXISTS=true
    IMAGE_DATE=$(sudo docker inspect -f '{{ .Created }}' ${IMAGE_NAME} 2>/dev/null | cut -d'T' -f1)
    IMAGE_STATUS="${GREEN}Built (${IMAGE_DATE})${NC}"
else
    IMAGE_EXISTS=false
    IMAGE_STATUS="${RED}Not built${NC}"
fi

# Display status
echo -e "${CYAN}Current Status:${NC}"
echo -e "  Image:     ${IMAGE_STATUS}"
echo -e "  Container: ${STATUS}"
if [ "$CONTAINER_RUNNING" = true ]; then
    echo -e "  URL:       ${GREEN}http://localhost:3000${NC}"
    PUBLIC_IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null)
    if [ ! -z "$PUBLIC_IP" ]; then
        echo -e "  External:  ${GREEN}http://${PUBLIC_IP}:3000${NC}"
    fi
fi
echo ""

# Menu
echo -e "${CYAN}What would you like to do?${NC}"
echo "  1) 🚀 Quick start (build if needed + run background)"
echo "  2) 🔨 Build image only"
echo "  3) ▶️  Run interactive (with live logs, Ctrl+C to stop)"
echo "  4) 🔄 Rebuild and restart"
echo "  5) ⏹️  Stop container"
echo "  6) 🗑️  Remove container"
echo "  7) 📋 View logs"
echo "  8) 🏃 Run in background (daemon mode)"
echo "  9) 🧹 Clean everything (images + container)"
echo "  0) ❌ Exit"
echo ""
read -p "Enter choice [0-9]: " choice

case $choice in
    1) # Quick start (background)
        echo -e "\n${YELLOW}Starting production deployment...${NC}"
        
        # Build if image doesn't exist
        if [ "$IMAGE_EXISTS" = false ]; then
            echo -e "${YELLOW}Building Docker image (ARM64)...${NC}"
            echo -e "${CYAN}This will take 5-8 minutes...${NC}"
            sudo docker build --no-cache --platform ${PLATFORM} -t ${IMAGE_NAME} .
            if [ $? -ne 0 ]; then
                echo -e "${RED}Build failed!${NC}"
                exit 1
            fi
            echo -e "${GREEN}✓ Build complete!${NC}"
        else
            echo -e "${GREEN}✓ Image already exists${NC}"
        fi
        
        # Stop if running
        if [ "$CONTAINER_RUNNING" = true ]; then
            echo -e "${YELLOW}Stopping existing container...${NC}"
            sudo docker stop ${CONTAINER_NAME}
        fi
        
        # Remove if exists
        if [ "$CONTAINER_EXISTS" = true ]; then
            echo -e "${YELLOW}Removing old container...${NC}"
            sudo docker rm ${CONTAINER_NAME}
        fi
        
        # Run container in background
        echo -e "${YELLOW}Starting container in background...${NC}"
        if [ -f "$ENV_FILE" ]; then
            sudo docker run -d -p ${PORT_MAPPING} \
                --env-file ${ENV_FILE} \
                -v ${DATA_VOLUME}:/app/backend/data \
                --name ${CONTAINER_NAME} \
                --restart unless-stopped \
                ${IMAGE_NAME}
        else
            echo -e "${YELLOW}No .env file found, running with defaults${NC}"
            sudo docker run -d -p ${PORT_MAPPING} \
                -v ${DATA_VOLUME}:/app/backend/data \
                --name ${CONTAINER_NAME} \
                --restart unless-stopped \
                ${IMAGE_NAME}
        fi
        
        echo -e "${GREEN}✓ Production server started in background!${NC}"
        echo -e "${GREEN}URL: http://localhost:3000${NC}"
        echo -e "${CYAN}View logs with: sudo docker logs -f ${CONTAINER_NAME}${NC}"
        ;;
        
    2) # Build only
        echo -e "\n${YELLOW}Building Docker image (ARM64)...${NC}"
        echo -e "${CYAN}This will take 5-8 minutes...${NC}"
        sudo docker build --no-cache --platform ${PLATFORM} -t ${IMAGE_NAME} .
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Build complete!${NC}"
        else
            echo -e "${RED}Build failed!${NC}"
            exit 1
        fi
        ;;
        
    3) # Run interactive (with live logs)
        if [ "$IMAGE_EXISTS" = false ]; then
            echo -e "\n${RED}Image not built yet! Run option 1 or 2 first.${NC}"
            exit 1
        fi
        
        if [ "$CONTAINER_RUNNING" = true ]; then
            echo -e "\n${YELLOW}Container already running! Stop it first.${NC}"
            exit 1
        fi
        
        # Remove if exists (stopped)
        if [ "$CONTAINER_EXISTS" = true ]; then
            echo -e "${YELLOW}Removing old container...${NC}"
            sudo docker rm ${CONTAINER_NAME}
        fi
        
        echo -e "\n${GREEN}Starting container with live logs...${NC}"
        echo -e "${GREEN}URL: http://localhost:3000${NC}"
        PUBLIC_IP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null)
        if [ ! -z "$PUBLIC_IP" ]; then
            echo -e "${GREEN}External: http://${PUBLIC_IP}:3000${NC}"
        fi
        echo -e "${YELLOW}Press Ctrl+C to stop the container${NC}\n"
        
        # Run interactively like the user is used to
        if [ -f "$ENV_FILE" ]; then
            sudo docker run -it --rm -p ${PORT_MAPPING} \
                --env-file ${ENV_FILE} \
                -v ${DATA_VOLUME}:/app/backend/data \
                --name ${CONTAINER_NAME} \
                ${IMAGE_NAME}
        else
            sudo docker run -it --rm -p ${PORT_MAPPING} \
                -v ${DATA_VOLUME}:/app/backend/data \
                --name ${CONTAINER_NAME} \
                ${IMAGE_NAME}
        fi
        
        echo -e "\n${YELLOW}Container stopped${NC}"
        ;;
        
    4) # Rebuild and restart
        echo -e "\n${YELLOW}Rebuilding and restarting...${NC}"
        
        # Stop and remove if exists
        if [ "$CONTAINER_EXISTS" = true ]; then
            echo -e "${YELLOW}Stopping and removing old container...${NC}"
            sudo docker stop ${CONTAINER_NAME} 2>/dev/null
            sudo docker rm ${CONTAINER_NAME}
        fi
        
        # Rebuild
        echo -e "${YELLOW}Building Docker image (ARM64)...${NC}"
        sudo docker build --no-cache --platform ${PLATFORM} -t ${IMAGE_NAME} .
        if [ $? -ne 0 ]; then
            echo -e "${RED}Build failed!${NC}"
            exit 1
        fi
        
        # Run new container
        echo -e "${YELLOW}Starting new container...${NC}"
        if [ -f "$ENV_FILE" ]; then
            sudo docker run -d -p ${PORT_MAPPING} \
                --env-file ${ENV_FILE} \
                -v ${DATA_VOLUME}:/app/backend/data \
                --name ${CONTAINER_NAME} \
                --restart unless-stopped \
                ${IMAGE_NAME}
        else
            sudo docker run -d -p ${PORT_MAPPING} \
                -v ${DATA_VOLUME}:/app/backend/data \
                --name ${CONTAINER_NAME} \
                --restart unless-stopped \
                ${IMAGE_NAME}
        fi
        
        echo -e "${GREEN}✓ Rebuild and restart complete!${NC}"
        echo -e "${GREEN}URL: http://localhost:3000${NC}"
        ;;
        
    5) # Stop
        if [ "$CONTAINER_RUNNING" = true ]; then
            echo -e "\n${YELLOW}Stopping container...${NC}"
            sudo docker stop ${CONTAINER_NAME}
            echo -e "${GREEN}✓ Container stopped${NC}"
        else
            echo -e "\n${YELLOW}Container is not running${NC}"
        fi
        ;;
        
    6) # Remove container
        if [ "$CONTAINER_EXISTS" = true ]; then
            if [ "$CONTAINER_RUNNING" = true ]; then
                echo -e "\n${YELLOW}Stopping container...${NC}"
                sudo docker stop ${CONTAINER_NAME}
            fi
            echo -e "${YELLOW}Removing container...${NC}"
            sudo docker rm ${CONTAINER_NAME}
            echo -e "${GREEN}✓ Container removed${NC}"
        else
            echo -e "\n${YELLOW}No container to remove${NC}"
        fi
        ;;
        
    7) # View logs
        if [ "$CONTAINER_EXISTS" = true ]; then
            echo -e "\n${CYAN}Showing last 50 lines (Ctrl+C to exit):${NC}\n"
            sudo docker logs -f --tail 50 ${CONTAINER_NAME}
        else
            echo -e "\n${RED}Container doesn't exist${NC}"
        fi
        ;;
        
    8) # Run in background
        if [ "$IMAGE_EXISTS" = false ]; then
            echo -e "\n${RED}Image not built yet! Run option 1 or 2 first.${NC}"
            exit 1
        fi
        
        if [ "$CONTAINER_RUNNING" = true ]; then
            echo -e "\n${YELLOW}Container already running!${NC}"
            exit 0
        fi
        
        if [ "$CONTAINER_EXISTS" = true ]; then
            echo -e "\n${YELLOW}Starting existing container...${NC}"
            sudo docker start ${CONTAINER_NAME}
        else
            echo -e "\n${YELLOW}Creating and starting container in background...${NC}"
            if [ -f "$ENV_FILE" ]; then
                sudo docker run -d -p ${PORT_MAPPING} \
                    --env-file ${ENV_FILE} \
                    -v ${DATA_VOLUME}:/app/backend/data \
                    --name ${CONTAINER_NAME} \
                    --restart unless-stopped \
                    ${IMAGE_NAME}
            else
                sudo docker run -d -p ${PORT_MAPPING} \
                    -v ${DATA_VOLUME}:/app/backend/data \
                    --name ${CONTAINER_NAME} \
                    --restart unless-stopped \
                    ${IMAGE_NAME}
            fi
        fi
        echo -e "${GREEN}✓ Container started in background!${NC}"
        echo -e "${GREEN}URL: http://localhost:3000${NC}"
        echo -e "${CYAN}View logs with: sudo docker logs -f ${CONTAINER_NAME}${NC}"
        ;;
9) # Clean everything
        echo -e "\n${RED}⚠️  This will remove:${NC}"
        echo "  - The OpenWebUI container"
        echo "  - The OpenWebUI image"
        echo "  - (Data volume will be preserved)"
        echo ""
        read -p "Are you sure? [y/N]: " confirm
        
        if [[ $confirm == [yY] ]]; then
            if [ "$CONTAINER_EXISTS" = true ]; then
                echo -e "${YELLOW}Removing container...${NC}"
                sudo docker stop ${CONTAINER_NAME} 2>/dev/null
                sudo docker rm ${CONTAINER_NAME}
            fi
            
            if [ "$IMAGE_EXISTS" = true ]; then
                echo -e "${YELLOW}Removing image...${NC}"
                sudo docker rmi ${IMAGE_NAME}
            fi
            
            echo -e "${GREEN}✓ Cleanup complete${NC}"
            echo -e "${CYAN}Note: Data volume preserved in '${DATA_VOLUME}'${NC}"
        else
            echo -e "${YELLOW}Cancelled${NC}"
        fi
        ;;
        
    0) # Exit
        echo -e "${GREEN}Goodbye!${NC}"
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}Done! Run './prod.sh' again for more options.${NC}"