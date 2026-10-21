# Review of the Article «Lakehouse: A New Generation of Open Platforms that Unify Data Warehousing and Advanced Analytics»

## INTRODUCTION

The article «Lakehouse: A New Generation of Open Platforms that Unify Data Warehousing and Advanced Analytics» was published in 2021 by Michael Armbrust, Ali Ghodsi, Reynold Xin, and Matei Zaharia at the Conference on Innovative Data Systems Research (CIDR).

The paper introduces the Lakehouse architecture, which combines the advantages of data lakes and data warehouses. The main objective is to demonstrate how a unified data platform can reduce infrastructure complexity, improve data reliability, and support both business intelligence and machine learning workloads.

## METHODOLOGY

The research combines architectural analysis with experimental performance evaluation. The authors examine the limitations of traditional data warehouses and data lakes, comparing their storage capabilities, processing efficiency, and support for advanced analytics.

To validate the proposed architecture, the researchers use the TPC-DS benchmark with 99 SQL queries and compare Databricks Delta Engine against four cloud data warehouses. Performance is evaluated through query execution time and computational costs. No separate statistical hypothesis testing is reported.

## RESULTS

The results demonstrate that Lakehouse architecture can provide competitive analytical performance while reducing processing costs.

In the TPC-DS benchmark, Delta Engine completed the workload in approximately 3,302 seconds, compared with 2,996–37,283 seconds for competing systems. Its execution cost was $104 using on-demand instances, compared with $153–$570 for the evaluated warehouses.

These findings suggest that open storage formats do not necessarily limit analytical performance. Furthermore, integrating storage and analytics reduces unnecessary data duplication and simplifies data management.

## KEY INSIGHTS

### 1. Unified Data Architecture Reduces Pipeline Complexity

A particularly useful insight concerns eliminating unnecessary data transfers between data lakes and warehouses. In practice, this means that data engineering teams can build pipelines around a shared storage layer instead of maintaining multiple synchronized datasets. This reduces the number of ETL operations, simplifies debugging, and helps prevent inconsistencies between analytical and operational data.

### 2. Open Data Formats Improve ML Workflow Flexibility

The use of Apache Parquet and other open formats enables different processing frameworks to access the same datasets. For teams implementing ML solutions, this means that Spark, Python-based tools, and machine learning frameworks can work with shared data without repeatedly exporting it from proprietary warehouses. This simplifies feature preparation, improves experiment reproducibility, and reduces additional storage requirements.

### 3. Transactional Metadata Improves Data Reliability

Another important insight is the role of ACID transactions and data versioning in reliable analytical systems. In practical data engineering work, versioned datasets make it possible to reproduce previous results, investigate pipeline failures, and restore earlier data states. This is especially valuable for ML workflows where consistent training datasets are necessary for comparing experiments and validating model performance.

## CONCLUSION

The article makes a significant contribution by demonstrating that Lakehouse architecture can combine efficient SQL analytics, open storage, and advanced machine learning support within one platform.

Its main strength is connecting architectural concepts with measurable performance results. However, broader independent benchmarking would strengthen the conclusions. Future research could investigate storage optimization, metadata management, serverless processing, and scalability under diverse production workloads.

Overall, the paper provides a practical foundation for designing modern, scalable data and machine learning platforms.
