#!/bin/bash

sed -i 's/Default: aws-quickstart/Default: 3decision-eu-central-1/g' ~/quickstart-discngine-3decision/templates/*
sed -i 's~quickstart-discngine-3decision/~'${1}'~g' ~/quickstart-discngine-3decision/templates/*
