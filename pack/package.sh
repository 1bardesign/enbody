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
mkdir enbody-win
cat ./win/love.exe enbody.love > enbody-win/enbody.exe
cp ./win/*.dll enbody-win
cp ./win/license.txt enbody-win/license_love2d.txt
cp ../readme.md enbody-win
cp ../license.txt enbody-win
zip -r enbody-win.zip enbody-win
rm -rf enbody-win
