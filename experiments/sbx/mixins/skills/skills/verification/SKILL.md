---
name: verification
description: Choose proportionate checks and report exactly what was and was not verified.
---

# Verification

Before changing code, identify the requested outcome and the smallest relevant check.
Run that check after the change. Distinguish a passing check from a check that was
not run, could not run, or does not cover the full runtime environment. Do not
claim an image build, integration test, or deployment smoke test from static
inspection alone.
