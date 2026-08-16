#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

LINKS_FILE="git-links.txt"

finish() {
    local exit_code=$1
    echo -e "\n${BLUE}Нажмите Enter, чтобы закрыть окно...${NC}"
    read -r
    exit "$exit_code"
}

die() {
    echo -e "${RED}$1${NC}" >&2
    finish 1
}

# проверки
if [ ! -f "$LINKS_FILE" ]; then
    die "Ошибка: Файл $LINKS_FILE не найден."
fi

CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
    die "Ошибка: Не удалось определить текущую ветку (detached HEAD?)."
fi

echo -e "${BLUE} Синхронизация репозиториев (локальная ветка: $CURRENT_BRANCH) ${NC}"

# коммиты
git add .

if git diff --cached --quiet; then
    echo -e "${YELLOW}Нет новых изменений для коммита. Переходим к отправке...${NC}"
else
    echo -e "${BLUE}Введите текст коммита:${NC}"
    read -r -p "> " COMMIT_MSG

    if [ -z "$COMMIT_MSG" ]; then
        die "Ошибка: Текст коммита не может быть пустым."
    fi

    if git commit -m "$COMMIT_MSG"; then
        echo -e "${GREEN}Коммит успешно создан.${NC}"
    else
        die "Ошибка при создании коммита."
    fi
fi

# чтение и пуш
echo -e "\n${BLUE}Отправка...${NC}"
HAS_ERROR=false
LINKS_FOUND=0
FAILED_URLS=()          # массив для хранения неудачных ссылок
FAILED_BRANCHES=()      # соответствующие им удалённые ветки

while IFS= read -r line || [[ -n "$line" ]]; do
    # убрать \r и лишние пробелы
    line=$(echo "$line" | tr -d '\r' | xargs)
    [[ -z "$line" || "$line" == \#* ]] && continue

    LINKS_FOUND=$((LINKS_FOUND + 1))

    read -r URL REMOTE_BRANCH <<< "$line"

    if [[ "$URL" == -* ]]; then
        echo -e "${RED}Пропуск $URL: адрес не должен начинаться с дефиса.${NC}"
        HAS_ERROR=true
        continue
    fi

    # если нет указания удаленной ветки в файле, то используется текущая
    [ -z "$REMOTE_BRANCH" ] && REMOTE_BRANCH="$CURRENT_BRANCH"

    echo -e "\n${BLUE}Отправка на: ${URL}${NC}"
    echo -e "Маршрут: ${CURRENT_BRANCH} -> ${REMOTE_BRANCH}"

    if git push -- "$URL" "${CURRENT_BRANCH}:${REMOTE_BRANCH}"; then
        echo -e "${GREEN}Успех.${NC}"
    else
        echo -e "${YELLOW}Не удалось отправить на $URL (вероятно, конфликты истории).${NC}"
        FAILED_URLS+=("$URL")
        FAILED_BRANCHES+=("$REMOTE_BRANCH")
    fi
done < "$LINKS_FILE"

if [ "$LINKS_FOUND" -eq 0 ]; then
    die "Ошибка: В файле $LINKS_FILE нет ни одной активной ссылки для отправки."
fi

if [ ${#FAILED_URLS[@]} -gt 0 ]; then
    echo -e "\n${RED}Следующие репозитории не удалось обновить обычным push:${NC}"
    for i in "${!FAILED_URLS[@]}"; do
        echo -e "  ${FAILED_URLS[$i]} (ветка: ${FAILED_BRANCHES[$i]})"
    done

    echo -e "\n${YELLOW}ВНИМАНИЕ: Принудительная отправка (--force) ПЕРЕЗАПИШЕТ историю на удаленных серверах.{$NC}"
    echo -e "Это может уничтожить чужие коммиты!${NC}"
    
    read -r -p "Введите 'yes', чтобы выполнить force push для этих репозиториев: " FORCE_CONFIRM

    if [[ "$FORCE_CONFIRM" == "yes" ]]; then
        echo -e "\n${BLUE}Выполняется принудительная отправка (--force)...${NC}"
        for i in "${!FAILED_URLS[@]}"; do
            URL="${FAILED_URLS[$i]}"
            REMOTE_BRANCH="${FAILED_BRANCHES[$i]}"
            
            echo -e "\n${BLUE}Force push на: ${URL}${NC}"
            if git push --force -- "$URL" "${CURRENT_BRANCH}:${REMOTE_BRANCH}"; then
                echo -e "${GREEN}Успех (force).${NC}"
            else
                echo -e "${RED}Ошибка при force push на $URL${NC}"
                HAS_ERROR=true
            fi
        done
    else
        echo -e "\n${RED}Принудительная отправка отклонена.${NC}"
        HAS_ERROR=true
    fi
fi

# резы
echo -e "\n *** "
if [ "$HAS_ERROR" = true ]; then
    echo -e "${RED}Завершено с ошибками. См. логи выше.${NC}"
    finish 1
else
    echo -e "${GREEN}Все операции успешно завершены.${NC}"
    finish 0
fi