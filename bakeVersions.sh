> current-pgator.version
echo $(git describe --abbrev=0 --tags)-$(git log --pretty=format:'%h' -n 1)  >> current-pgator.version
