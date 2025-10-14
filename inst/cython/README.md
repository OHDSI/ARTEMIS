# 1. Prepare  build env (py-end)
Requirements:
* python=3.12 (as ARTEMIS run on this version)
* numpy
* cython
* setuptools
* wheel
* tqdm (Optional - to run compare-test)

## 1.1. Example via mamba
`mamba create -n tsw-env python=3.12 numpy cython setuptools wheel tqdm -y`
`activate tsw-env`

# 2. Build cmd (py-end)
 
`python setup.py build_ext --inplace`
`python3 setup.py build_ext --inplace`

This should create a bunch of stuff "."

## 2.1. Once built, you should create a py module...
I did not get to a point of setting it up automatically, so instead just create 
**TSW_Package** directory manually and place compiled functions there... 
It should look like this:

```
TSW_Package/
├── align_TSW.cpython-312-x86_64-linux-gnu.so
├── find_best_score.cpython-312-x86_64-linux-gnu.so
├── TSW_scoreMat.cpython-312-x86_64-linux-gnu.so
└── __init__.py
```

## 2.2. make sure functionality is sourced from __init__.py

```
# __init__.py
from .TSW_scoreMat import TSW_scoreMat as TSWc
from .find_best_score import find_best_score as fbs
from .align_TSW import aTSW

__all__ = ["TSWc", "fbs", "aTSW"]
```

# 3. Run 

## 3.1. (optional)
Lastly in compare-test.py make sure sys has the TSW module in path

`cd benchmark && python compare-test.py`

## 3.2. Main
Make sure TSW_Package is avilable in `python/main.py` 

## 3.3. Run userScript
