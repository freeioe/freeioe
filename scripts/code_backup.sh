mkdir -p __backup
mkdir -p __release
git archive master | tar -x -C __backup
tar -zcf __release/code.tar.gz __backup
rm -rf __backup

