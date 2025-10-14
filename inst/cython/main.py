import numpy as np
import pandas as pd
import math as math

# --- ADD TSW_Package to sys.path
import sys, os

# Full path to the current script
# current_file = os.path.abspath(__file__)
# current_dir = os.path.dirname(current_file)
# Build absolute path to ../cython/TSW_Package (or compiled .so)
# cython_dir = os.path.abspath(current_dir)  # normalize path
# Add to Python path so you can import
# sys.path.append(cython_dir)
from TSW_Package import align_patients_regimens_fast


pd.options.display.max_columns = None


def align_patients_regimens(
    patients,
    regimens,
    col_name_patient_id="person_id",
    col_name_patient_record="seq",
    col_name_regimens="shortString",
    col_name_regName="regName",
    g=0.4,
    T=0.5,
    s=None,
    verbose=0,
    mem=-1,
    removeOverlap=1,
    method="PropDiff",
):
    return align_patients_regimens_fast(
        patients,
        regimens,
        col_name_patient_id="person_id",
        col_name_patient_record="seq",
        col_name_regimens="shortString",
        col_name_regName="regName",
        g=0.4,
        T=0.5,
        s=None,
        verbose=0,
        mem=-1,
        removeOverlap=1,
        method="PropDiff",
    )


def main():
    # Example input for testing
    # patients = pd.read_csv("example_patients.csv")
    # regimens = pd.read_csv("example_regimens.csv")
    patients = pd.DataFrame(
        {
            "person_id": ["test1"],
            "seq": [
                "0.cisplatin;0.pemetrexed;21.cisplatin;0.pemetrexed;42.cisplatin;0.pemetrexed;"
            ],
        }
    )

    regimens = pd.DataFrame(
        {
            "regName": ["Regimen1"],
            "shortString": ["14.pemetrexed;14.pemetrexed;"],
        }
    )

    df = align_patients_regimens(patients, regimens)
    print(df)
    print("Python module loaded successfully.")


# This ensures the main function runs only when the script is executed directly
if __name__ == "__main__":
    main()
