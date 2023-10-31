# Appcircle _Testinium_ component

Run your test plans with Testinium

## Required Inputs

- `AC_TESTINIUM_APP_PATH`: Full path of the build. For example $AC_EXPORT_DIR/Myapp.ipa
- `AC_TESTINIUM_USERNAME`: Testinium username.
- `AC_TESTINIUM_PASSWORD`: Testinium password.
- `AC_TESTINIUM_PROJECT_ID`: Testinium project ID.
- `AC_TESTINIUM_PLAN_ID`: Testinium plan ID.
- `AC_TESTINIUM_TIMEOUT`: Testinium plan timeout in seconds.
- `AC_TESTINIUM_COMPANY_ID`: Testinium company ID.

## Optional Inputs

- `AC_TESTINIUM_MAX_FAIL_PERCENTAGE`: Maximum failure percentage limit to interrupt workflow. It must be in the range 1-100.
