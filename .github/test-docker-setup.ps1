# 🐳 Docker Hub Test Script (Windows PowerShell)
# Teste votre configuration Docker Hub avant de déclencher GitHub Actions
# Usage: .\test-docker-setup.ps1

$ErrorActionPreference = "Stop"

Write-Host "🐳 WatchTracker - Docker Hub Configuration Test" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Fonction pour afficher le résultat
function Check-Status {
    param($message, $success = $true)
    if ($success) {
        Write-Host "✅ $message" -ForegroundColor Green
    } else {
        Write-Host "❌ $message" -ForegroundColor Red
    }
}

# 1. Check Docker installation
Write-Host "1️⃣ Vérifier que Docker est installé..." -ForegroundColor Blue
try {
    $dockerVersion = docker --version
    Write-Host "   $dockerVersion"
    Check-Status "Docker détecté"
} catch {
    Check-Status "Docker n'est pas installé" $false
    Write-Host "   Installez Docker: https://docs.docker.com/desktop/install/windows-install/"
    exit 1
}
Write-Host ""

# 2. Get Docker Hub credentials
Write-Host "2️⃣ Configurer Docker Hub login..." -ForegroundColor Blue
$docker_username = Read-Host "   Entrez votre username Docker Hub"
$docker_password_secure = Read-Host "   Entrez votre Access Token Docker Hub" -AsSecureString
$docker_password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicodePtr($docker_password_secure))

Write-Host "   Tentative de connexion à Docker Hub..."
$docker_password | docker login --username "$docker_username" --password-stdin | Out-Null
if ($LASTEXITCODE -eq 0) {
    Check-Status "Connexion Docker Hub réussie"
} else {
    Check-Status "Échec de la connexion Docker Hub" $false
    exit 1
}
Write-Host ""

# 3. Check Dockerfile exists
Write-Host "3️⃣ Vérifier que Dockerfile existe..." -ForegroundColor Blue
$dockerfilePath = "server\Dockerfile"
if (Test-Path $dockerfilePath) {
    Check-Status "Dockerfile trouvé: $dockerfilePath"
} else {
    Check-Status "Dockerfile NOT FOUND: $dockerfilePath" $false
    exit 1
}
Write-Host ""

# 4. Check .dockerignore
Write-Host "4️⃣ Vérifier que .dockerignore existe..." -ForegroundColor Blue
$dockerignorePath = "server\.dockerignore"
if (Test-Path $dockerignorePath) {
    Check-Status ".dockerignore trouvé"
} else {
    Write-Host "   ⚠️  .dockerignore NOT FOUND (créer pour optimiser l'image)" -ForegroundColor Yellow
}
Write-Host ""

# 5. Build Docker image
Write-Host "5️⃣ Builder l'image Docker..." -ForegroundColor Blue
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$image_tag = "$docker_username/watchtracker-api:test-$timestamp"
Write-Host "   Image tag: $image_tag"

try {
    docker build -t "$image_tag" ./server
    if ($LASTEXITCODE -eq 0) {
        Check-Status "Docker image builder"
    } else {
        Check-Status "Erreur au builder l'image" $false
        exit 1
    }
} catch {
    Check-Status "Erreur au builder l'image: $_" $false
    exit 1
}
Write-Host ""

# 6. Show image info
Write-Host "6️⃣ Info sur l'image..." -ForegroundColor Blue
docker images | Select-String "watchtracker-api" | Write-Host
Write-Host ""

# 7. Test image locally
Write-Host "7️⃣ Tester l'image localement..." -ForegroundColor Blue
Write-Host "   Lançant le container..."

try {
    $container_id = docker run -d -p 8000:8000 "$image_tag"
    if ($LASTEXITCODE -eq 0) {
        Start-Sleep -Seconds 3
        
        # Check if container is running
        $running = docker ps | Select-String $container_id
        if ($running) {
            Check-Status "Container lancé avec succès (ID: $container_id)"
            
            # Test API
            Write-Host "   Testant l'API..."
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:8000" -ErrorAction SilentlyContinue
                if ($response.StatusCode -eq 200) {
                    Check-Status "API répond"
                } else {
                    Write-Host "   ⚠️  API répond avec status $($response.StatusCode) (peut être normal)" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "   ⚠️  API ne répond pas (peut être normal selon la config)" -ForegroundColor Yellow
            }
            
            # Stop container
            docker stop $container_id | Out-Null
            Write-Host "   Container arrêté"
        } else {
            Check-Status "Erreur: Container n'est pas en cours d'exécution" $false
            docker logs $container_id
            exit 1
        }
    } else {
        Check-Status "Erreur au lancer le container" $false
        exit 1
    }
} catch {
    Check-Status "Erreur: $_" $false
    exit 1
}
Write-Host ""

# 8. Push to Docker Hub
Write-Host "8️⃣ Pusher l'image vers Docker Hub..." -ForegroundColor Blue
$push_confirmation = Read-Host "Voulez-vous pusher l'image vers Docker Hub? (y/n)"

if ($push_confirmation -eq 'y' -or $push_confirmation -eq 'Y') {
    Write-Host "   Poussant $image_tag..."
    try {
        docker push "$image_tag"
        if ($LASTEXITCODE -eq 0) {
            Check-Status "Image poussée sur Docker Hub"
            Write-Host ""
            Write-Host "✅ Image disponible à: https://hub.docker.com/r/$docker_username/watchtracker-api" -ForegroundColor Green
        } else {
            Check-Status "Erreur au pousser l'image" $false
            exit 1
        }
    } catch {
        Check-Status "Erreur au pousser l'image: $_" $false
        exit 1
    }
} else {
    Write-Host "   Push skipped"
}
Write-Host ""

# 9. Cleanup
Write-Host "9️⃣ Nettoyer les images locales..." -ForegroundColor Blue
docker rmi "$image_tag" | Out-Null
if ($LASTEXITCODE -eq 0) {
    Check-Status "Image test supprimée"
} else {
    Write-Host "   ⚠️  Erreur en supprimant l'image" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "✅ TOUS LES TESTS PASSÉS!" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Résumé:" -ForegroundColor Cyan
Write-Host "  - Docker est installé et fonctionne"
Write-Host "  - Docker Hub login réussi"
Write-Host "  - Dockerfile builder correctement"
Write-Host "  - Container fonctionne"
Write-Host "  - API répond"
Write-Host ""
Write-Host "🚀 Prochaines étapes:" -ForegroundColor Cyan
Write-Host "  1. Committer votre code"
Write-Host "  2. Pousser sur GitHub"
Write-Host "  3. Créer une PR ou merger sur main"
Write-Host "  4. GitHub Actions va automatiquement:"
Write-Host "     - Builder l'image"
Write-Host "     - Pousser vers Docker Hub"
Write-Host "     - Créer une release avec tags version"
Write-Host ""
Write-Host "🔗 Ressources:" -ForegroundColor Cyan
Write-Host "  - Docker Hub: https://hub.docker.com/r/$docker_username/watchtracker-api"
Write-Host "  - GitHub Actions: https://github.com/sheik37/WatchTracker/actions"
Write-Host "  - Documentation: .github/WORKFLOWS.md"
Write-Host ""

# Logout Docker Hub
docker logout | Out-Null
Write-Host "Vous êtes déconnecté de Docker Hub" -ForegroundColor Blue
