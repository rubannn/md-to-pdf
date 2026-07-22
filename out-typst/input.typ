#import "../style/style.typ": apply-style
#show: apply-style

#set document(
  title: "Review: Machine Learning Operations MLOps : Challenges and Strategies",
  author: "Mykola Ruban",
  description: "Review: Machine Learning Operations MLOps : Challenges and Strategies",
  keywords: ("typst", "pdf", "review", "mlops", "challenges", "strategies", "article", "technical"),
)


= Review: Machine Learning Operations (MLOps): Challenges and Strategies

== Introduction

The article «Machine Learning Operations (MLOps): Challenges and Strategies», authored by Amandeep Singla and published in the International Journal of Advanced Computer Science and Applications (Vol. 15, No. 1, 2023), addresses the growing importance of MLOps as a discipline streamlining the end-to-end ML lifecycle — development, deployment, monitoring, and maintenance. The central research question concerns why organizations struggle to operationalize ML models at scale and what strategies can mitigate the technical, organizational, and cultural obstacles involved. The paper's goal is to categorize the main challenges of MLOps adoption and propose strategies for achieving efficiency, scalability, and reliability in ML workflows.

== Methodology

The paper is a conceptual review rather than an empirical study. Instead of surveys, experiments, or statistical analysis, the author synthesizes existing knowledge and industry practice into a taxonomy of challenges, grouped into three categories — technical, organizational, and cultural — each discussed narratively and grounded in established DevOps principles. No dataset, sample size, or quantitative metric is reported, placing the work closer to a position paper than a data-driven research article.

== Results

The key findings center on three challenge domains. Technical challenges include model versioning, reproducibility, and consistent performance across heterogeneous environments. Organizational challenges involve coordinating cross-functional teams, managing fragmented toolchains, and integrating ML pipelines into existing development processes. Cultural challenges include resistance to change, skill gaps, and lack of shared vocabulary between data scientists and engineers. The author proposes strategies such as version control and containerization, dedicated MLOps teams, integrating MLOps into DevOps, automated CI/CD pipelines, and continuous education programs.

== Key insights

*_Reproducibility as an infrastructure problem, not a discipline problem._* The article frames reproducibility failures as arising from inconsistent environments and weak version control rather than a lack of rigor among practitioners. This reframes reproducibility as solvable through tooling — containerization, dataset versioning, model registries — directly transferable to any pipeline mixing structured data processing with ML components.

*_MLOps as an extension of DevOps rather than a separate discipline._* The recommendation to embed MLOps within existing DevOps practices suggests that CI/CD principles familiar from traditional software engineering apply almost directly to ML systems, reducing the learning curve for teams moving between these domains.

*_Cultural friction as a leading cause of failed adoption._* By naming resistance to change and terminology gaps as obstacles, the article highlights that technical solutions alone are insufficient — cross-functional communication and shared documentation are equally critical for a pipeline to be trusted long-term.

== Conclusion

Overall, the article offers a useful conceptual map of MLOps challenges and strategies, contributing to the field by consolidating scattered industry observations into a structured framework. Its main limitation is the absence of empirical validation — no case studies, interviews, or quantitative evidence support the proposed strategies. Future research could test the framework against real-world implementations, measuring the actual impact of the proposed measures on deployment reliability and adoption rates.