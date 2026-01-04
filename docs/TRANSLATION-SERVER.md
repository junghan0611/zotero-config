# Zotero Translation Server - Headless URL Saving

브라우저나 Zotero GUI 없이 URL을 Zotero에 저장하는 방법입니다.

---

## 개요

**Translation Server**는 Zotero의 URL 메타데이터 추출 기능을 HTTP API로 제공하는 서버입니다.
이를 활용하면 CLI, 스크립트, Emacs 등에서 직접 Zotero에 아이템을 저장할 수 있습니다.

```
URL → Translation Server (메타데이터 추출) → Zotero Web API (저장)
```

---

## 1. Translation Server 설치

### 방법 1: Docker (권장)

```bash
# 일회성 실행
docker run -d -p 1969:1969 --name zotero-translation zotero/translation-server

# 자동 재시작 설정 (시스템 부팅 시 자동 시작)
docker run -d -p 1969:1969 --name zotero-translation \
  --restart unless-stopped \
  zotero/translation-server
```

### 방법 2: Podman (rootless)

```bash
podman run -d -p 1969:1969 --name zotero-translation \
  docker.io/zotero/translation-server
```

### 방법 3: systemd 사용자 서비스

```bash
# 서비스 파일 생성
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/zotero-translation.service << 'EOF'
[Unit]
Description=Zotero Translation Server
After=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/docker run --rm --name zotero-translation -p 1969:1969 zotero/translation-server
ExecStop=/usr/bin/docker stop zotero-translation
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=default.target
EOF

# 서비스 활성화
systemctl --user daemon-reload
systemctl --user enable --now zotero-translation
```

### 동작 확인

```bash
curl http://localhost:1969
# 응답: "Zotero Translation Server is running"
```

---

## 2. Zotero API 키 발급

1. https://www.zotero.org/settings/keys 접속
2. **"Create new private key"** 클릭
3. 설정:
   - Name: `Translation Server CLI`
   - **Allow library access**: ✅ Read/Write
   - **Allow notes access**: ✅ (선택)
4. **Save Key** 클릭 후 API 키 복사

**User ID 확인**: 같은 페이지 상단에 `Your userID for use in API calls is XXXXXX` 형태로 표시

---

## 3. 환경 변수 설정

```bash
# ~/.bashrc 또는 ~/.zshrc에 추가
export ZOTERO_API_KEY="your_api_key_here"
export ZOTERO_USER_ID="your_user_id_here"
export ZOTERO_TRANSLATION_SERVER="http://localhost:1969"
```

설정 적용:
```bash
source ~/.bashrc
```

---

## 4. CLI 사용

### 기본 사용법

```bash
# 스크립트 위치
cd ~/zotero-config/scripts

# URL 저장
./zotero-save-url.sh "https://arxiv.org/abs/2103.00020"

# 특정 컬렉션에 저장
./zotero-save-url.sh "https://www.nature.com/articles/s41586-021-03819-2" "COLLECTION_KEY"
```

### 클립보드에서 저장 (X11)

```bash
# 클립보드 URL 저장
./zotero-save-url.sh "$(xclip -o)"

# 또는 xsel 사용
./zotero-save-url.sh "$(xsel --clipboard)"
```

### i3wm 키바인딩

```bash
# ~/.config/i3/config에 추가
bindsym $mod+z exec --no-startup-id ~/zotero-config/scripts/zotero-save-url.sh "$(xclip -o)" && notify-send "Zotero" "URL saved!"
```

---

## 5. Emacs 통합

### 설치

```elisp
;; Doom Emacs: config.el에 추가
(load! "~/zotero-config/scripts/zotero-save.el")

(setq zotero-api-key (getenv "ZOTERO_API_KEY")
      zotero-user-id (getenv "ZOTERO_USER_ID"))
```

### 사용법

| 명령어 | 설명 |
|--------|------|
| `M-x zotero-save-url` | URL 입력하여 저장 |
| `M-x zotero-save-url-at-point` | 커서 위치의 URL 저장 |
| `M-x zotero-save-org-link` | Org-mode 링크 저장 |
| `M-x zotero-save-clipboard` | 클립보드 URL 저장 |
| `M-x zotero-check-server` | 서버 상태 확인 |

### Doom Emacs 키바인딩

```
SPC n z u  →  zotero-save-url
SPC n z p  →  zotero-save-url-at-point
SPC n z l  →  zotero-save-org-link
SPC n z c  →  zotero-save-clipboard
SPC n z s  →  zotero-check-server
```

---

## 6. 고급 사용법

### 직접 API 호출

```bash
# 1. Translation Server에서 메타데이터 추출
METADATA=$(curl -s -X POST \
  -H "Content-Type: text/plain" \
  -d "https://arxiv.org/abs/2103.00020" \
  http://localhost:1969/web)

echo "$METADATA" | jq .

# 2. Zotero API로 저장
curl -X POST \
  -H "Zotero-API-Key: $ZOTERO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$METADATA" \
  "https://api.zotero.org/users/$ZOTERO_USER_ID/items"
```

### 컬렉션 목록 조회

```bash
curl -H "Zotero-API-Key: $ZOTERO_API_KEY" \
  "https://api.zotero.org/users/$ZOTERO_USER_ID/collections" | jq .
```

### PDF 다운로드 및 첨부

```bash
# PDF URL을 Translation Server로 처리 후 저장
# (Translation Server가 PDF 메타데이터도 추출 가능)
./zotero-save-url.sh "https://arxiv.org/pdf/2103.00020.pdf"
```

---

## 7. 문제 해결

### Translation Server가 응답하지 않음

```bash
# Docker 컨테이너 상태 확인
docker ps -a | grep zotero-translation

# 컨테이너 재시작
docker restart zotero-translation

# 로그 확인
docker logs zotero-translation
```

### API 인증 오류 (403)

- API 키에 Write 권한이 있는지 확인
- User ID가 올바른지 확인 (숫자만, 문자열 아님)

### 메타데이터 추출 실패

일부 사이트는 Translation Server가 지원하지 않을 수 있습니다.
이 경우 기본 webpage 아이템으로 저장됩니다.

```bash
# 지원 여부 테스트
curl -X POST -H "Content-Type: text/plain" \
  -d "https://example.com" \
  http://localhost:1969/web
```

---

## 8. 관련 리소스

- [Zotero Translation Server GitHub](https://github.com/zotero/translation-server)
- [Zotero Web API Documentation](https://www.zotero.org/support/dev/web_api/v3/start)
- [pyzotero - Python Zotero API Client](https://github.com/urschrei/pyzotero)

---

## 요약

| 단계 | 명령어 |
|------|--------|
| 서버 시작 | `docker run -d -p 1969:1969 zotero/translation-server` |
| 환경 변수 설정 | `export ZOTERO_API_KEY=... ZOTERO_USER_ID=...` |
| URL 저장 | `./zotero-save-url.sh "https://..."` |
| Emacs | `M-x zotero-save-url-at-point` |

이제 GUI 없이 어디서든 Zotero에 링크를 저장할 수 있습니다!
