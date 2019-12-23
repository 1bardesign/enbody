#!/bin/bash

#initial setup
rm -rf dist
rm enbody.love
rm enbody-win.zip

#raw love2d file
cd ..
zip -r pack/enbody.love *.lua readme.md license.txt
cd pack


#windows
mkdir dist
cat ./win/love.exe enbody.love > dist/enbody.exe
cp ./win/*.dll dist
cp ./win/license.txt dist/license_love2d.txt
cp ../readme.md dist
cp ../license.txt dist
cd dist
zip -r ../enbody-win.zip .
cd ..
rm -rf dist
