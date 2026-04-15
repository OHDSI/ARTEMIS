# Releases

Notice: Due to bundled data requirements, users are encouraged to utilize Git’s built-in versioning features for deployment and package management.

1. main latest 
```
git clone --branch v1.2.0 https://github.com/OHDSI/ARTEMIS.git
```

2. previous version 
```
git clone --branch [v1.1.0] https://github.com/OHDSI/ARTEMIS.git
```

In any time user can view the current releases:  
``gh release list``

Also, easy start a new update branch:
```
git checkout -b <hotfix-for-v1.2.0>
```

and contribute with a Pull Request.

Important note: 
Please consult us if you plan to use non-main branch for diagnostics.