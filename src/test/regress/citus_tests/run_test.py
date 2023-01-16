#!/usr/bin/env python3

import sys
import os
import pathlib
from glob import glob
import argparse
import shutil
import random
import re
import common
import config

args = argparse.ArgumentParser()
args.add_argument("test_name", help="Test name (must be included in a schedule.)", nargs='?')
args.add_argument("-p", "--path", required=False, help="Relative path for test file (must have a .sql or .spec extension)", type=pathlib.Path)
args.add_argument("-r", "--repeat", help="Number of test to run", type=int, default=1)
args.add_argument("-b", "--use-base-schedule", required=False, help="Choose base-schedules rather than minimal-schedules", action='store_true')
args.add_argument("-w", "--use-whole-schedule-line", required=False, help="Use the whole line found in related schedule", action='store_true')

args = vars(args.parse_args())

regress_dir = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
test_file_path = args['path']
test_file_name = args['test_name']
use_base_schedule = args['use_base_schedule']
use_whole_schedule_line = args['use_whole_schedule_line']

test_files_to_skip = ['multi_cluster_management', 'multi_extension', 'multi_test_helpers', 'multi_insert_select']
test_files_to_run_without_schedule = ['single_node_enterprise']

if not (test_file_name or test_file_path):
    print(f"FATAL: No test given.")
    sys.exit(2)


if test_file_path:
    test_file_path = os.path.join(os.getcwd(), args['path'])

    if not os.path.isfile(test_file_path):
        print(f"ERROR: test file '{test_file_path}' does not exist")
        sys.exit(2)

    test_file_extension = pathlib.Path(test_file_path).suffix
    test_file_name = pathlib.Path(test_file_path).stem

    if not test_file_extension in '.spec.sql':
        print(
            "ERROR: Unrecognized test extension. Valid extensions are: .sql and .spec"
        )
        sys.exit(1)

# early exit if it's a test that needs to be skipped
if test_file_name in test_files_to_skip:
    print(f"WARNING: Skipping exceptional test: '{test_file_name}'")
    sys.exit(0)

test_schedule = ''

# find related schedule
for schedule_file_path in sorted(glob(os.path.join(regress_dir, "*_schedule"))):
        for schedule_line in open(schedule_file_path, 'r'):
            if  re.search(r'\b' + test_file_name + r'\b', schedule_line):
                test_schedule = pathlib.Path(schedule_file_path).stem
                if use_whole_schedule_line:
                    test_schedule_line = schedule_line
                else:
                    test_schedule_line = f"test: {test_file_name}\n"
                break
        else:
            continue
        break

# map suitable schedule
if not test_schedule:
    print(
        f"WARNING: Could not find any schedule for '{test_file_name}'"
    )
    sys.exit(0)
elif "isolation" in test_schedule:
    test_schedule = 'base_isolation_schedule'
elif "failure" in test_schedule:
    test_schedule = 'failure_base_schedule'
elif "enterprise" in test_schedule:
    test_schedule = 'enterprise_minimal_schedule'
elif "split" in test_schedule:
    test_schedule = 'minimal_schedule'
elif "mx" in test_schedule:
    if use_base_schedule:
        test_schedule = 'mx_base_schedule'
    else:
        test_schedule = 'mx_minimal_schedule'
elif "operations" in test_schedule:
    test_schedule = 'minimal_schedule'
elif test_schedule in config.ARBITRARY_SCHEDULE_NAMES:
    print(f"WARNING: Arbitrary config schedule ({test_schedule}) is not supported.")
    sys.exit(0)
else:
    if use_base_schedule:
        test_schedule = 'base_schedule'
    else:
        test_schedule = 'minimal_schedule'

# copy base schedule to a temp file and append test_schedule_line
# to be able to run tests in parallel (if test_schedule_line is a parallel group.)
tmp_schedule_path = os.path.join(regress_dir, f"tmp_schedule_{ random.randint(1, 10000)}")
# some tests don't need a schedule to run
# e.g tests that are in the first place in their own schedule
if test_file_name not in test_files_to_run_without_schedule:
    shutil.copy2(os.path.join(regress_dir, test_schedule), tmp_schedule_path)
with open(tmp_schedule_path, "a") as myfile:
        for i in range(args['repeat']):
            if test_schedule_line.startswith('test: upgrade_') and '_after' in test_schedule_line:
                # Assume that given test schedule line belongs to "after-upgrade" phase of an
                # upgrade test when the above condition holds. This is not a great way to detect
                # after-upgrade tests but seems like a safe assumption atm.
                #
                # And if that's the case, replace all the occurrences of '_after' with '_before'
                # to deduce a schedule line for "before-upgrade" phase. We need to add the
                # corresponding before-schedule before each after-schedule line because the tests
                # that belong to after-upgrade tests depend on the objects created earlier.
                #
                # e.g.:
                #   "test: upgrade_basic_after upgrade_type_after upgrade_ref2ref_after"
                # becomes
                #   "test: upgrade_basic_before upgrade_type_before upgrade_ref2ref_before"
                before_sql_schedule_line = test_schedule_line.replace('_after', '_before')
                myfile.write(before_sql_schedule_line)
            myfile.write(test_schedule_line)

# find suitable make recipe
if "isolation" in test_schedule:
    make_recipe = 'check-isolation-custom-schedule'
elif "failure" in test_schedule:
    make_recipe = 'check-failure-custom-schedule'
else:
    make_recipe = 'check-custom-schedule'

# prepare command to run tests
test_command = f"make -C {regress_dir} {make_recipe} SCHEDULE='{pathlib.Path(tmp_schedule_path).stem}'"

# run test command n times
try:
    print(f"Executing.. {test_command}")
    result = common.run(test_command)
finally:
    # remove temp schedule file
    os.remove(tmp_schedule_path)
