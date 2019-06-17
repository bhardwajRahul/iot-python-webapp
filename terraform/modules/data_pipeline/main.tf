# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY IOT REGISTRY ALONG WITH DATA INGESTION ALONG WITH NoSQL DB AND DATA WAREHOUSE
# This module creates an iot registry, pubsub topics, dataflow jobs
# , bigtable instance and cluster, and bigquery dataset/table
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY IOT REGISTRY AND ALIGNED PUBSUB TOPICS
# ---------------------------------------------------------------------------------------------------------------------
resource "google_cloudiot_registry" "iot-registry" {
  name   = var.iot_registry_name
  region = var.location

  event_notification_config = {
    pubsub_topic_name = google_pubsub_topic.data-pipeline-topic.id
  }

  state_notification_config = {
    pubsub_topic_name = google_pubsub_topic.iot-device-status.id
  }

  http_config = {
    http_enabled_state = var.http_config_state
  }

  mqtt_config = {
    mqtt_enabled_state = var.mqtt_config_state
  }

  # credentials {
  #   public_key_certificate = {
  #     format      = "X509_CERTIFICATE_PEM"
  #     certificate = "rsa_cert.pem"
  #   }
  # }
}

resource "google_pubsub_topic" "data-pipeline-topic" {
  name    = var.data_pipeline_topic_name
  project = var.project

  labels = {
    version = var.version_label
  }
}

resource "google_pubsub_topic" "iot-device-status" {
  name    = var.device_status_topic_name
  project = var.project

  labels = {
    version = var.version_label
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY BIGQUERY DATASET AND TABLE WITH DEFINED SCHEMA
# ---------------------------------------------------------------------------------------------------------------------
resource "google_bigquery_dataset" "iot_dataset" {
  dataset_id  = var.dataset_name
  description = var.dataset_desc
  project     = var.project
  location    = "US"

  labels = {
    version = var.version_label
  }
}

resource "google_bigquery_table" "iot_raw_data" {
  dataset_id  = google_bigquery_dataset.iot_dataset.dataset_id
  table_id    = var.table_name
  description = var.table_desc

  time_partitioning {
    field = var.partition_field_name
    type  = "DAY"
  }

  labels = {
    version = var.version_label
  }

  schema = "${file("${path.module}/schemas/bigquery_schema.json")}"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY BIGTABLE INSTANCE WITH EMPTY TABLE
# ---------------------------------------------------------------------------------------------------------------------
resource "google_bigtable_instance" "iot-stream-database" {
  name          = var.bigtable_db_name
  instance_type = var.bigtable_db_instance_type #change to PRODUCTION when ready

  cluster {
    cluster_id = var.bigtable_db_cluster_name
    zone       = var.zone

    # num_nodes    = 0
    storage_type = var.bigtable_db_storage_type
  }
}

resource "google_bigtable_table" "iot-stream-table" {
  name          = var.bigtable_table_name
  instance_name = google_bigtable_instance.iot-stream-database.name
  column_family {
    family = var.bigtable_column_family
  }
  split_keys = var.bigtable_table_split_keys
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY DATAFLOW JOB TO INGEST IOT DEVICE DATA INTO BIGQUERY
# ---------------------------------------------------------------------------------------------------------------------
resource "google_dataflow_job" "dataflow-raw-data-stream" {
  name                  = var.dataflow_raw_data_job_name
  service_account_email = var.service_account_email
  template_gcs_path     = var.template_gcs_path_location
  temp_gcs_location     = var.temp_staging_gcs_path
  zone                  = var.zone
  on_delete             = var.on_delete_option
  parameters = {
    inputTopic      = google_pubsub_topic.data-pipeline-topic.id
    outputTableSpec = google_bigquery_table.iot_raw_data.id
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY CLOUD FUNCTION TO INGEST IOT DEVICE DATA FROM PUBSUB AND WRITE TO BIGTABLE
# ---------------------------------------------------------------------------------------------------------------------

# https://codelabs.developers.google.com/codelabs/cpb104-bigtable-cbt/#5
# https://github.com/GoogleCloudPlatform/python-docs-samples/blob/master/bigtable/hello/main.py
# may need to use cloud function to send data from pubsub
# into bigtable using the python api
# but this will make the pipeline code feel fragmented
resource "google_storage_bucket" "bucket" {
  name = "test-bucket"
}

resource "google_storage_bucket_object" "archive" {
  name   = "index.zip"
  bucket = "${google_storage_bucket.bucket.name}"
  source = "./path/to/zip/file/which/contains/code"
}


resource "google_cloudfunctions_function" "big-table-function" {
  name        = "big-table-function"
  description = "My function"
  runtime     = "nodejs10"

  available_memory_mb   = 256
  source_archive_bucket = "${google_storage_bucket.bucket.name}"
  source_archive_object = "${google_storage_bucket_object.archive.name}"
  trigger_http          = true
  timeout               = 60
  entry_point           = "helloGET"
  labels = {
    my-label = "my-label-value"
  }

  environment_variables = {
    MY_ENV_VAR = "my-env-var-value"
  }
}
