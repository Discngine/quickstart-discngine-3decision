# How To update

This function targets the AWS Lambda **python3.14** runtime and uses
[`python-oracledb`](https://python-oracledb.readthedocs.io/) in Thin mode
(no Oracle Instant Client libraries required).

## Update only the handler code

If you only changed `lambda_function.py`:

```
zip -ur package.zip *.py
```

## Rebuild the full package (e.g. to bump dependencies or the Python version)

`oracledb` and its dependencies ship platform/Python-specific binary wheels, so
they must be fetched for the Lambda runtime's platform (linux x86_64) and Python
version — not your local machine's:

```
rm -rf build && mkdir -p build/pkg

# Download wheels for the Lambda runtime (cp314 / manylinux x86_64)
python3 -m pip download oracledb \
  --only-binary=:all: \
  --python-version 3.14 --implementation cp --abi cp314 \
  --platform manylinux2014_x86_64 --platform manylinux_2_17_x86_64 \
  -d build/wheels

# Unpack every wheel flat into the package root
for w in build/wheels/*.whl; do unzip -qo "$w" -d build/pkg; done

# Add the handler and zip it up
cp lambda_function.py build/pkg/
(cd build/pkg && zip -qr9 ../../package.zip . -x "*.pyc" "*/__pycache__/*")
```

If you bump the Lambda `runtime` in `terraform/modules/secrets/main.tf`, update
the `--python-version`/`--abi` flags above to match (e.g. `3.15` / `cp315`).
