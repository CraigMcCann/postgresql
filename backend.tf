terraform {
  backend "pg" {
    conn_str = "postgres://<postgres server fqdn>/terraform_state"
  }
}
