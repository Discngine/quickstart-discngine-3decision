#!/bin/bash

cd ~/quickstart-discngine-3decision/templates/
sed -i 's/Default: aws-quickstart/Default: 3decision-eu-central-1/g' $(ls -p | grep -v /)
sed -i 's~quickstart-discngine-3decision/~'${1}'~g' $(ls -p | grep -v /)
