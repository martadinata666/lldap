#!/bin/bash
git checkout main
git pull
git checkout personal
git rebase --autosquash main personal
git push origin personal --force
