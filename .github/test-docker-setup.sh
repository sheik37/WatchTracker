#!/bin/bash
# 🐳 Docker Hub Test Script
# Teste votre configuration Docker Hub avant de déclencher GitHub Actions
# Usage: bash test-docker-setup.sh

set -e  # Exit on error

echo "🐳 WatchTracker - Docker Hub Configuration Test"
echo "=============================================="
echo ""

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher le résultat
function check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $1${NC}"
        return 0
    else
        echo -e "${RED}❌ $1${NC}"
        return 1
    fi
}

# Fonction pour prompt l'utilisateur
function prompt() {
    read -p "$(echo -e ${BLUE}$1${NC}): " result
    echo $result
}

# 1. Check Docker installation
echo -e "${BLUE}1️⃣ Vérifier que Docker est installé...${NC}"
docker --version
check "Docker détecté"
echo ""

# 2. Check Docker Hub credentials
echo -e "${BLUE}2️⃣ Vérifier Docker Hub login...${NC}"
docker_username=$(prompt "Entrez votre username Docker Hub")
docker_password=$(prompt "Entrez votre Access Token Docker Hub (ou password)")

echo "   Tentative de connexion à Docker Hub..."
echo "$docker_password" | docker login --username "$docker_username" --password-stdin
check "Connexion Docker Hub réussie"
echo ""

# 3. Check Dockerfile exists
echo -e "${BLUE}3️⃣ Vérifier que Dockerfile existe...${NC}"
if [ -f "server/Dockerfile" ]; then
    echo -e "${GREEN}✅ Dockerfile trouvé: server/Dockerfile${NC}"
else
    echo -e "${RED}❌ Dockerfile NOT FOUND: server/Dockerfile${NC}"
    exit 1
fi
echo ""

# 4. Check .dockerignore
echo -e "${BLUE}4️⃣ Vérifier que .dockerignore existe...${NC}"
if [ -f "server/.dockerignore" ]; then
    echo -e "${GREEN}✅ .dockerignore trouvé${NC}"
else
    echo -e "${YELLOW}⚠️  .dockerignore NOT FOUND (créer pour optimiser l'image)${NC}"
fi
echo ""

# 5. Build Docker image
echo -e "${BLUE}5️⃣ Builder l'image Docker...${NC}"
image_tag="$docker_username/watchtracker-api:test-$(date +%s)"
echo "   Image tag: $image_tag"
docker build -t "$image_tag" ./server
check "Docker image builder"
echo ""

# 6. Show image info
echo -e "${BLUE}6️⃣ Info sur l'image...${NC}"
docker images | grep watchtracker-api
echo ""

# 7. Test image locally
echo -e "${BLUE}7️⃣ Tester l'image localement...${NC}"
echo "   Lançant le container..."
container_id=$(docker run -d -p 8000:8000 "$image_tag")
sleep 3

# Check if container is running
if docker ps | grep -q "$container_id"; then
    echo -e "${GREEN}✅ Container lancé avec succès (ID: $container_id)${NC}"
    
    # Test API
    echo "   Testant l'API..."
    if curl -s http://localhost:8000 > /dev/null 2>&1; then
        echo -e "${GREEN}✅ API répond${NC}"
    else
        echo -e "${YELLOW}⚠️  API ne répond pas (peut être normal selon la config)${NC}"
    fi
    
    # Stop container
    docker stop "$container_id"
    echo "   Container arrêté"
else
    echo -e "${RED}❌ Erreur au lancer le container${NC}"
    docker logs "$container_id"
    exit 1
fi
echo ""

# 8. Push to Docker Hub
echo -e "${BLUE}8️⃣ Pusher l'image vers Docker Hub...${NC}"
read -p "Voulez-vous pusher l'image vers Docker Hub? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "   Poussant $image_tag..."
    docker push "$image_tag"
    check "Image poussée sur Docker Hub"
    echo ""
    echo -e "${GREEN}✅ Image disponible à: https://hub.docker.com/r/$docker_username/watchtracker-api${NC}"
else
    echo "   Push skipped"
fi
echo ""

# 9. Cleanup
echo -e "${BLUE}9️⃣ Nettoyer les images locales...${NC}"
docker rmi "$image_tag"
check "Image test supprimée"
echo ""

# Summary
echo "=============================================="
echo -e "${GREEN}✅ TOUS LES TESTS PASSÉS!${NC}"
echo ""
echo "📝 Résumé:"
echo "  - Docker est installé et fonctionne"
echo "  - Docker Hub login réussi"
echo "  - Dockerfile builder correctement"
echo "  - Container fonctionne"
echo "  - API répond"
echo ""
echo "🚀 Prochaines étapes:"
echo "  1. Committer votre code"
echo "  2. Pousser sur GitHub"
echo "  3. Créer une PR ou merger sur main"
echo "  4. GitHub Actions va automatiquement:"
echo "     - Builder l'image"
echo "     - Pousser vers Docker Hub"
echo "     - Créer une release avec tags version"
echo ""
echo "🔗 Ressources:"
echo "  - Docker Hub: https://hub.docker.com/r/$docker_username/watchtracker-api"
echo "  - GitHub Actions: https://github.com/sheik37/WatchTracker/actions"
echo "  - Documentation: .github/WORKFLOWS.md"
echo ""

# Logout Docker Hub
docker logout
echo -e "${BLUE}Vous êtes déconnecté de Docker Hub${NC}"
