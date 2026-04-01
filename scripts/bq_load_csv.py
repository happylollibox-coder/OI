#!/usr/bin/env python3
"""
Load a CSV file into a BigQuery table using the Python client.
Used when the bq CLI is not in PATH (e.g. in Cursor/IDE).
Usage: bq_load_csv.py <project_id> <dataset.table> <csv_path> <schema>
  schema = comma-separated "name:TYPE" e.g. "col1:STRING,col2:INTEGER,col3:DATE"
"""
import sys

def main():
    if len(sys.argv) != 5:
        print("Usage: bq_load_csv.py <project_id> <dataset.table> <csv_path> <schema>", file=sys.stderr)
        sys.exit(1)
    project_id, table_ref, csv_path, schema_str = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

    try:
        from google.cloud import bigquery
    except ImportError:
        print("Install: pip install google-cloud-bigquery", file=sys.stderr)
        sys.exit(1)

    # Parse schema "name:TYPE,name:TYPE,..."
    schema_fields = []
    for part in schema_str.split(","):
        part = part.strip()
        if ":" not in part:
            continue
        name, bq_type = part.split(":", 1)
        name, bq_type = name.strip(), bq_type.strip().upper()
        if bq_type == "INTEGER":
            bq_type = "INT64"
        elif bq_type == "FLOAT":
            bq_type = "FLOAT64"
        schema_fields.append(bigquery.SchemaField(name, bq_type))

    client = bigquery.Client(project=project_id)
    table_id = f"{project_id}.{table_ref}"

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        schema=schema_fields,
        autodetect=False,
    )

    with open(csv_path, "rb") as f:
        job = client.load_table_from_file(f, table_id, job_config=job_config)
    job.result()
    print(f"Loaded {job.output_rows} row(s) into {table_id}.")
    sys.exit(0)


if __name__ == "__main__":
    main()
