```
python -m build
pip install dist/smhi-0.1-py3-none-any.whl
```

```
python3 smhi/main.py
```

The seeding process is generally IO bound. It's therefore fine to set CORES higher than the cores available on the CPU.
