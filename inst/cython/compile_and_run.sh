rm -f TSW_Package
rm *.so
rm *.c
rm *.o

mkdir TSW_Package

python3 setup.py build_ext --inplace
cp *.so TSW_Package/
cp __init__.py TSW_Package/

rm -rf build
rm *.c
python3 main.py    
