#!/bin/bash
export PATH=../../dmd2/osx/bin:$PATH

rdmd -unittest --main adjustxml.d
