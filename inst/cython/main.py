import numpy as np
import pandas as pd
import math as math

import sys, os
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
    method="PropDiff",
):
    return align_patients_regimens_fast(
        patients,
        regimens,
        col_name_patient_id=col_name_patient_id,
        col_name_patient_record=col_name_patient_record,
        col_name_regimens=col_name_regimens,
        col_name_regName=col_name_regName,
        g=g,
        T=T,
        s=s,
        verbose=verbose,
        mem=mem,
        method=method,
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
    # print(df)
    print("Cython module loaded successfully.")


# This ensures the main function runs only when the script is executed directly
if __name__ == "__main__":
    main()
