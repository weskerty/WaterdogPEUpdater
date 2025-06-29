#!/bin/bash
set -e

#cd "$(dirname "$(realpath "$0")")"/../waterdog || {
#  echo "❌ No se pudo entrar a ../waterdog"
#  exit 1
#}


# Configs

GITHUB_TOKEN=""
# Requerido para Actions 

JAVAVER=/usr/lib/jvm/java-11-openjdk/bin/java
# Version Java a Usar

JAR_NAME="Waterdog.jar"
ZIP_NAME="waterdog.zip"

















check_need_download() {
  local remote_date="$1"
  local source_name="$2"
  
  if [[ -f "$JAR_NAME" ]]; then
    LOCAL_DATE=$(date -r "$JAR_NAME" -Iseconds)
    echo "📁 Local: $LOCAL_DATE"
    
    REMOTE_TIMESTAMP=$(date -d "$remote_date" +%s)
    LOCAL_TIMESTAMP=$(date -d "$LOCAL_DATE" +%s)
    
    if [[ $LOCAL_TIMESTAMP -ge $REMOTE_TIMESTAMP ]]; then
      echo "✅ Local ya actualizado ($source_name)"
      return 1  
    else
      echo "📥 Version nueva disponible ($source_name)"
      return 0  
    fi
  else
    echo "📁 Archivo local no encontrado"
    return 0  
  fi
}

download_from_artifacts() {
  echo "🔧 Buscando artifacts..."
  
  if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "⚠️ GITHUB_TOKEN no configurado, saltando artifacts"
    return 1
  fi
  
  ARTIFACTS_JSON=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/WaterdogPE/WaterdogPE/actions/artifacts?per_page=20" 2>/dev/null || echo "")
  
  if [[ -z "$ARTIFACTS_JSON" ]]; then
    echo "⚠️ No se pudo obtener artifacts"
    return 1
  fi
  
  ARTIFACT_DATA=$(echo "$ARTIFACTS_JSON" | jq -r '
    [.artifacts[] | select(.name == "waterdog" and .expired == false)] |
    sort_by(.created_at) | reverse |
    .[0] | 
    {
      id: .id,
      date: .created_at,
      workflow_run: .workflow_run.head_sha[0:7]
    }
  ' 2>/dev/null || echo "null")
  
  ARTIFACT_ID=$(echo "$ARTIFACT_DATA" | jq -r '.id')
  ARTIFACT_DATE=$(echo "$ARTIFACT_DATA" | jq -r '.date')
  WORKFLOW_SHA=$(echo "$ARTIFACT_DATA" | jq -r '.workflow_run')
  
  if [[ "$ARTIFACT_ID" == "null" || -z "$ARTIFACT_ID" ]]; then
    echo "⚠️ No artifact 'waterdog' válido"
    return 1
  fi
  
  echo "🔧 Artifact: ID=$ARTIFACT_ID | SHA=$WORKFLOW_SHA | $ARTIFACT_DATE"
  
  if ! check_need_download "$ARTIFACT_DATE" "artifact"; then
    return 0  
  fi
  
  echo "⬇️ Descargando artifact..."
  
  # artifact
  if curl -L -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/WaterdogPE/WaterdogPE/actions/artifacts/$ARTIFACT_ID/zip" \
    -o "$ZIP_NAME"; then
    
    echo "📦 Extrayendo $ZIP_NAME..."
    
    # Extraer Waterdog.jar
    if unzip -q -o "$ZIP_NAME" && [[ -f "Waterdog.jar" ]]; then
      rm -f "$ZIP_NAME"
      echo "✅ $JAR_NAME actualizado desde ARTIFACT."
      return 0
    else
      echo "❌ Error al extraer Waterdog.jar en ZIP"
      rm -f "$ZIP_NAME"
      return 1
    fi
  else
    echo "❌ Error al descargar ARTIFACT"
    return 1
  fi
}

download_from_releases() {
  echo "🌐 Buscando releases..."
  
  RELEASE_JSON=$(wget -qO- "https://api.github.com/repos/WaterdogPE/WaterdogPE/releases?per_page=10" || echo "")
  
  if [[ -z "$RELEASE_JSON" ]]; then
    echo "❌ No se pudo obtener releases"
    return 1
  fi
  
  RELEASE_DATA=$(echo "$RELEASE_JSON" | jq -r '
    [.[] | select(.assets[] | .name == "Waterdog.jar")] |
    sort_by(.published_at) | reverse |
    .[0] | 
    {
      url: (.assets[] | select(.name == "Waterdog.jar") | .browser_download_url),
      date: .published_at,
      tag: .tag_name,
      prerelease: .prerelease
    }
  ' 2>/dev/null || echo "null")
  
  JAR_URL=$(echo "$RELEASE_DATA" | jq -r '.url')
  RELEASE_DATE=$(echo "$RELEASE_DATA" | jq -r '.date')
  TAG_NAME=$(echo "$RELEASE_DATA" | jq -r '.tag')
  PRERELEASE=$(echo "$RELEASE_DATA" | jq -r '.prerelease')
  
  if [[ "$JAR_URL" == "null" || -z "$JAR_URL" ]]; then
    echo "❌ No release valido"
    return 1
  fi
  
  echo "📦 Release: $TAG_NAME | Prerelease: $PRERELEASE | $RELEASE_DATE"
  
  if ! check_need_download "$RELEASE_DATE" "release"; then
    return 0  
  fi
  
  echo "⬇️ Descargando release..."
  if wget -q --show-progress -O "$JAR_NAME" "$JAR_URL"; then
    echo "✅ $JAR_NAME actualizado desde release."
    return 0
  else
    echo "❌ Error al descargar release"
    return 1
  fi
}

# 
echo "🚀 Buscando actualizaciones..."

if download_from_artifacts; then
  echo "✅ Actualización completada desde ARTIFACTS"
elif download_from_releases; then
  echo "✅ Actualización completada desde RELEASES"
else
  echo "❌ No se pudo actualizar desde ninguna fuente"
  if [[ ! -f "$JAR_NAME" ]]; then
    echo "❌ No hay archivo local disponible"
    exit 1
  else
    echo "⏭️ Usando archivo local existente"
  fi
fi

if [[ ! -f "$JAR_NAME" ]]; then
  echo "❌ El archivo $JAR_NAME no existe."
  exit 1
fi

# Iniciar
echo "🚀 Iniciando $JAR_NAME...

"
java \
  -Dio.netty.tryReflectionSetAccessible=true \
  --add-opens java.base/jdk.internal.misc=ALL-UNNAMED \
  -Xms512M -Xmx2G \
  --enable-native-access=ALL-UNNAMED \
  -jar "$JAR_NAME"
