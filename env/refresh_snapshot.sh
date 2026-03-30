#!/bin/bash

# Delete cached environment snapshots and re-run full activation to
# rebuild them. Run this after changing env/activate, requirements*.txt,
# alire.toml, adding/removing __init__.py files (which affect the Python
# path), or anything else that influences the environment.
#
# Usage (inside container):
#   ./refresh_snapshot.sh
#
# Usage (via adamant_env.sh from host):
#   ./adamant_env.sh refresh

this_dir=`dirname "$0"`

if test -z "$ADAMANT_DIR"
then
    export ADAMANT_DIR=`readlink -f "$this_dir/../../adamant"`
fi

# Clear adamant's cached state without activating, since this repo's
# activate will chain into adamant's activate.
. $ADAMANT_DIR/env/refresh_snapshot.sh --no-activate

rm -f /tmp/.adamant_example_env_snapshot
unset EXAMPLE_ENVIRONMENT_SET
. $this_dir/activate
