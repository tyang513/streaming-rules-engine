#!/usr/bin/env bash

basedir=$(pwd)

usage()
{
  cat <<EOF
Usage: ${0##*/} <branch_name> <-r|--release|-fb|--feature-branch|-hb|--hotfix-branch>
  
  branch_name: 需要进行操作的分支名称,版本号规则为 X.Y.Z 其中必须全为数字

  Options:
    -r, --release          : 发布指定分支版本,发布后当前版本 X.Y.Z-SNAPSHOT 变为 X.Y.Z
    -fb, --feature-branch  : 通过已发布的分支创建功能开始分支,分支版本号为 branch_name 版本的次版本号加 1
    -hb, --hotfix-branch   : 通过已发布的分支创建缺陷修复分支,分支版本号为 branch_name 版本的修订版本号加 1
  
  Example:
    ${0##*/} main -r
EOF
  exit 1
}

# if no args specified, show usage
[ $# -gt 1 ] || usage

echo "当前目录为: $basedir"

main_branch_name="$1"

# 使用Git命令检查分支是否存在
if ! git rev-parse --verify "$main_branch_name" >/dev/null 2>&1; then
  echo "分支 '$main_branch_name' 不存在"
  exit 1
fi

# 使用shift移除第一个参数
shift

release() {

    git checkout $1
    if [ $? -ne 0 ]; then
        #/ 命令执行失败
        echo "切换到分支 $1 失败"
        exit 1
    fi
     

    git pull
    echo "git pull"

    version_snapshot=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive exec:exec)
    echo "项目版本号: $version_snapshot"

    # 检查版本号是否包含 -SNAPSHOT
    if [[ $version_snapshot == *-SNAPSHOT* ]]; then
        echo "版本号包含 -SNAPSHOT"
    else
        echo "版本号不包含 -SNAPSHOT"
        exit 1
    fi

    version=$(echo $version_snapshot | sed 's/-SNAPSHOT$//')
    echo "当前版本号: $version"

    tag_name=v$version
    if git rev-parse --verify "refs/tags/$tag_name" >/dev/null 2>&1; then
        echo "版本 $version 的 '$tag_name' 已经存在"
        exit 1
    fi

    mvn versions:set -DnewVersion=$version
    echo "versions set $version"

    find . -type f -name "pom.xml" -exec git add {} \;
    echo "git add 所有pom.xml"

    git commit -m "update version to $version"
    echo "git commit update version to $version"

    mvn clean package

    mvn install

    commit_id=$(git log -1 --pretty=format:%h)

    git tag -a $tag_name $commit_id -m "release version $tag_name"
    git push origin $tag_name
    git push
}
# 增加版本号中指定位置的数字
# 参数1: 版本号，如 "1.2.3"
# 参数2: 要增加的位置，0表示主版本号，1表示次版本号，2表示修订号
newVersion() {
    local version="$1"
    local position="${2:-2}"

    # 分割版本号
    IFS='.' read -ra parts <<< "$version"

    # 确保版本号格式正确
    if [ ${#parts[@]} -lt 3 ]; then
        echo "版本号格式不正确,必须为 X.Y.Z 格式"
        exit 1
    fi

    # 根据不同的位置修改版本号
    if [ "$position" == "0" ]; then
        parts[0]=$((parts[0] + 1))
        parts[1]=0
        parts[2]=0
    elif [ "$position" == "1" ]; then
        parts[1]=$((parts[1] + 1))
        parts[2]=0
    elif [ "$position" == "2" ]; then
        parts[2]=$((parts[2] + 1))
    fi

    # 增加指定位置的数字
    parts[$position]=$((parts[$position] + 1))

    # 重新构建版本号
    local new_version="${parts[0]}.${parts[1]}.${parts[2]}"

    echo "$new_version"
}

feature_branch() {

    git checkout $1
    if [ $? -ne 0 ]; then
        #/ 命令执行失败
        echo "切换到分支 $1 失败"
        exit 1
    fi

    new_version=$(newVersion "$version" 1)-SNAPSHOT

    branch_name=feature-$new_version

    git checkout -b $branch_name
    if [ $? -ne 0 ]; then
        #/ 命令执行失败
        echo "创建 feature 分支 $branch_name 失败"
        exit 1
    fi

    mvn versions:set -DnewVersion=$new_version

    find . -type f -name "pom.xml" -exec git add {} \;  # 将所有修改添加到暂存区
    git commit -m "创建新版本分支 $new_version"  # 提交修改
    git push origin $branch_name
}

hotfix_branch() {

    git checkout $1
    if [ $? -ne 0 ]; then
        #/ 命令执行失败
        echo "切换到分支 $1 失败"
        exit 1
    fi

    master_version=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive exec:exec)
    echo "master 项目版本号: $master_version"

    hotfix_new_version=$(newVersion "$master_version" 2)-SNAPSHOT

    hotfix_branch_name=hotfix-$hotfix_new_version

    git checkout -b $hotfix_branch_name
    if [ $? -ne 0 ]; then
        #/ 命令执行失败
        echo "创建 hotfix 分支 $hotfix_branch_name 失败"
        exit 1
    fi

    mvn versions:set -DnewVersion=$hotfix_new_version

    find . -type f -name "pom.xml" -exec git add {} \;  # 将所有修改添加到暂存区
    git commit -m "创建 hotfix 版本分支 $hotfix_new_version"  # 提交修改
    git push origin $hotfix_branch_name
}

# get arguments
while [ $# -ge 1 ]; then
  nameStartOpt="$2"
  echo $nameStartOpt
  shift
  case "$nameStartOpt" in
    (-r | --release)
      release $main_branch_name
      ;;
    (-fb | --feature-branch)
      feature_branch $main_branch_name
      ;;
    (-hb | --hotfix-branch)
      hotfix_branch $main_branch_name
    (*)
      echo $usage
      exit 1
      ;;
  esac
  shift
done

exit $?