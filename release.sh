#!/usr/bin/env bash

basedir=$(pwd)

git pull
echo "git pull"

version_snapshot=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive exec:exec)
echo "项目版本号: $version_snapshot"

version=$(echo $version_snapshot | sed 's/-SNAPSHOT$//')
echo "当前版本号: $version"

mvn versions:set -DnewVersion=$version
echo "versions set $version"

git add **/pom.xml
echo "git add 所有pom.xml"

git commit -m "update version to $version"
echo "git commit update version to $version"

mvn clean package

mvn install

tag_name=v$version

commit_id=$(git log -1 --pretty=format:%h)

git tag -a $tag_name $commit_id -m "release version $tag_name"
git push origin $tag_name
git push

newVersion() {
    local version="$1"
    local position="$2"

    # 检查是否为空，如果为空，则设置默认值为 3
    if [ -z "$position" ]; then
        position=2  # 默认为修订号
    fi

    # 分割版本号
    IFS='.' read -ra parts <<< "$version"

    # 确保版本号格式正确
    if [ ${#parts[@]} -lt 3 ]; then
        echo "版本号格式不正确,必须为 X.Y.Z 格式"
        exit 1
    fi

    # 增加指定位置的数字
    parts[$position]=$((parts[$position] + 1))

    # 重新构建版本号
    local new_version="${parts[0]}.${parts[1]}.${parts[2]}"

    echo "$new_version"
}

new_version=$(newVersion "$version" "$position")-SNAPSHOT

branch_name=feature-$new_version

git checkout -b $branch_name
mvn versions:set -DnewVersion=$new_version

git add **/pom.xml  # 将所有修改添加到暂存区
git commit -m "创建新版本分支 $new_version"  # 提交修改
git push origin $branch_name
