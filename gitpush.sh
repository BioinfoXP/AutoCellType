#!/bin/bash

# ==========================================
#  Git 协作助手脚本 (安全增强版)
# ==========================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 基础检查函数 ---

# 获取当前分支名称
get_current_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED_HEAD"
}

# 检查是否在 Git 仓库目录
if [ ! -d ".git" ] && [ ! -f ".git" ]; then
    echo -e "${RED}错误: 当前目录不是 Git 仓库！请进入正确的目录。${NC}"
    exit 1
fi

BRANCH=$(get_current_branch)

# 检查是否处于游离指针状态 (Detached HEAD)
if [ "$BRANCH" == "DETACHED_HEAD" ]; then
    echo -e "${RED}严重警告: 当前处于 Detached HEAD 状态（无具体分支）。${NC}"
    echo -e "请先 Checkout 到具体分支再使用此脚本。"
    exit 1
fi

# --- 菜单显示 ---
show_menu() {
    echo -e "\n${BLUE}==============================================${NC}"
    echo -e "  Git 助手 (当前分支: ${YELLOW}${BRANCH}${BLUE})  "
    echo -e "${BLUE}==============================================${NC}"
    echo "1. 查看状态 (git status)"
    echo "2. 拉取更新 (pull --rebase)"
    echo "3. 提交并推送 (add + commit + rebase + push)"
    echo "4. 仅推送 (先 rebase 同步，再 push)"
    echo -e "${RED}5. 强制推送 (git push --force)${NC}"
    echo "0. 退出"
    echo -e "${BLUE}==============================================${NC}"
}

# --- 主循环 ---
while true; do
    show_menu
    read -p "请输入选项 [0-5]: " choice
    echo ""

    case $choice in
        1)
            # 选项 1: 查看状态
            git status
            ;;
            
        2)
            # 选项 2: 安全拉取
            echo -e "${YELLOW}正在使用 Rebase 模式从 origin/${BRANCH} 拉取代码...${NC}"
            # --autostash: 自动暂存本地未提交的修改，防止冲突报错
            if git pull --rebase --autostash origin "$BRANCH"; then
                echo -e "${GREEN}拉取成功！历史线保持整洁。${NC}"
            else
                echo -e "${RED}拉取失败或存在冲突！${NC}"
                echo -e "${YELLOW}请手动解决冲突后运行 'git rebase --continue'${NC}"
            fi
            ;;
            
        3)
            # 选项 3: 标准提交流程
            git status -s
            echo ""
            
            # A. 检查是否有文件变更
            if [ -z "$(git status --porcelain)" ]; then
                echo -e "${YELLOW}工作区是干净的，没有需要提交的文件。${NC}"
            else
                # B. 获取 Commit 信息
                read -p "请输入 Commit 信息 (直接回车默认为 'Update'): " msg
                msg=${msg:-"Update"}
                
                # C. 执行 Add 和 Commit
                echo -e "${GREEN}执行: git add .${NC}"
                git add .
                
                echo -e "${GREEN}执行: git commit${NC}"
                git commit -m "$msg"
                
                # D. Commit 成功后，先拉取远程代码（Rebase）
                if [ $? -eq 0 ]; then
                    echo -e "${YELLOW}正在同步远程代码 (Rebase)...${NC}"
                    if git pull --rebase --autostash origin "$BRANCH"; then
                        # E. 拉取成功无冲突，执行推送
                        echo -e "${GREEN}同步成功，正在推送...${NC}"
                        git push origin "$BRANCH"
                        echo -e "${GREEN}🎉 操作全部完成！${NC}"
                    else
                        # F. 拉取遇到冲突，熔断停止
                        echo -e "${RED}⛔ 同步时发生冲突，推送已终止！${NC}"
                        echo -e "${YELLOW}您的 Commit 已保存。请手动解决冲突后，再执行 git push。${NC}"
                    fi
                fi
            fi
            ;;
            
        4)
            # 选项 4: 仅推送（含预同步）
            echo -e "${YELLOW}为了防止覆盖他人代码，推送前先同步 (Rebase)...${NC}"
            if git pull --rebase --autostash origin "$BRANCH"; then
                echo -e "${GREEN}同步完成，执行推送...${NC}"
                git push origin "$BRANCH"
                echo -e "${GREEN}🎉 推送完成！${NC}"
            else
                echo -e "${RED}⛔ 同步时发生冲突，推送已终止！${NC}"
            fi
            ;;
            
        5)
            # 选项 5: 强制推送（高危）
            echo -e "${RED}⚠️  警告：强制推送 (Force Push) 是破坏性操作！${NC}"
            echo -e "${RED}这会覆盖远程仓库的历史记录，可能导致同事的代码丢失。${NC}"
            read -p "请输入 'yes' 以确认执行强制推送: " confirm
            
            if [ "$confirm" == "yes" ]; then
                echo -e "${GREEN}正在执行: git push --force origin $BRANCH${NC}"
                git push --force origin "$BRANCH"
                echo -e "${GREEN}强制推送完成。${NC}"
            else
                echo -e "${YELLOW}操作已取消。${NC}"
            fi
            ;;
            
        0)
            echo "Bye!"
            exit 0
            ;;
            
        *)
            echo -e "${RED}无效选项，请重试。${NC}"
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
done