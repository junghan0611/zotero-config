# lib-install.sh — 공유 staging 설치 규율 (source 전용, 실행 파일 아님)
#
# 렌더는 항상 **목적지와 같은 디렉터리** 안의 숨김 staging 파일에 먼저 쓰고,
# 바이트가 실제로 달라졌을 때만 rename 으로 교체한다.
#   · 같은 파일시스템 rename → 부분적으로 쓰인 파일이 citar/bibcli 의 glob 에 안 보인다
#   · 바이트 동일이면 손대지 않는다 → mtime 보존 → Syncthing 에 no-op 전파 없음
#
# Zotero 렌더러와 GitHub starred 렌더러가 같은 규율을 쓰도록 여기 한 곳에 둔다.

# install_staged <staged> <target>
install_staged() {
    local staged="$1" target="$2"
    # 기존 파일이 있으면 그 mode 를 이어받는다 (일상적인 같은-사용자 쓰기).
    if [[ -e "$target" ]]; then
        chmod --reference="$target" "$staged"
    fi
    mv -f "$staged" "$target"
}
