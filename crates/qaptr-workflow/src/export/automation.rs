//! Automation-oriented Markdown rendering.

use std::fmt::Write as _;

use crate::{document::WorkflowDocument, export};

/// Renders an explicit, descriptive automation plan without executing anything.
pub fn render(workflow: &WorkflowDocument) -> String {
    let mut output = String::new();
    export::heading(
        &mut output,
        1,
        &format!(
            "Automation Procedure: {}",
            export::safe_text(&workflow.title)
        ),
    );
    output.push_str(
        "> Descriptive plan only. Qaptr does not launch tools, emit executable commands, or execute automations.\n\n",
    );

    export::heading(&mut output, 2, "Automation boundary");
    export::bullet(&mut output, "Execution status", "NOT EXECUTED BY QAPTR");
    export::bullet(
        &mut output,
        "Automation contract",
        "Translate the observed actions below into a separately reviewed implementation; this export itself performs no action",
    );
    export::confidence(&mut output, "Workflow evidence", &workflow.confidence);
    output.push('\n');

    export::heading(&mut output, 2, "Purpose and preconditions");
    export::bullet(
        &mut output,
        "Goal",
        workflow
            .goal
            .as_deref()
            .unwrap_or("No workflow goal was captured; do not infer one"),
    );
    export::bullet(
        &mut output,
        "Context",
        workflow
            .context
            .as_deref()
            .unwrap_or("No operating context was captured"),
    );
    output.push('\n');
    export::render_artifact_list(
        &mut output,
        "Inputs",
        &workflow.inputs,
        "No inputs were captured; an automation author must establish them separately.",
    );

    export::heading(&mut output, 2, "Observed tool capabilities");
    if workflow.tools.is_empty() {
        output.push_str(
            "No tools were captured. This export does not guess a tool or capability.\n\n",
        );
    } else {
        for tool in &workflow.tools {
            let purpose = tool
                .purpose
                .as_deref()
                .unwrap_or("Purpose was not captured");
            let observed_usage = tool
                .observed_usage
                .as_deref()
                .unwrap_or("Usage detail was not captured");
            let _ = writeln!(
                output,
                "- **{}** — {}. Observed use: {}",
                export::safe_text(&tool.name),
                export::safe_text(purpose),
                export::safe_text(observed_usage)
            );
            export::confidence(&mut output, "  Evidence", &tool.confidence);
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "Procedure model");
    if workflow.steps.is_empty() {
        output.push_str(
            "No steps were captured. There is no procedure to automate until a person supplies and reviews the missing sequence.\n\n",
        );
    } else {
        for (index, step) in workflow.steps.iter().enumerate() {
            let _ = writeln!(
                output,
                "{}. **{}** — {}",
                index + 1,
                export::safe_text(&step.name),
                export::safe_text(&step.action)
            );
            if let Some(rationale) = &step.rationale {
                export::bullet(&mut output, "  Why", rationale);
            }
            if !step.inputs.is_empty() {
                export::bullet(&mut output, "  Consumes", &step.inputs.join(", "));
            }
            if !step.outputs.is_empty() {
                export::bullet(&mut output, "  Produces", &step.outputs.join(", "));
            }
            if !step.tools.is_empty() {
                export::bullet(&mut output, "  Tool capabilities", &step.tools.join(", "));
            }
            export::confidence(&mut output, "  Evidence", &step.confidence);
            let _ = writeln!(output);
        }
    }

    export::heading(&mut output, 2, "Branching logic");
    if workflow.decision_points.is_empty() {
        output.push_str(
            "No decision points were captured. Do not add branches based on assumption.\n\n",
        );
    } else {
        for decision in &workflow.decision_points {
            let _ = writeln!(
                output,
                "- **Condition:** {}",
                export::safe_text(&decision.question)
            );
            export::bullet(
                &mut output,
                "Observed path",
                decision
                    .observed_answer
                    .as_deref()
                    .unwrap_or("The selected path was not captured"),
            );
            for alternative in &decision.alternatives {
                let _ = writeln!(
                    output,
                    "  - If {} → {}",
                    export::safe_text(&alternative.condition),
                    export::safe_text(&alternative.outcome)
                );
            }
            export::confidence(&mut output, "  Evidence", &decision.confidence);
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "Known variations");
    if workflow.variations.is_empty() {
        output.push_str("No variations were captured. This is not evidence that none exist.\n\n");
    } else {
        for variation in &workflow.variations {
            let _ = writeln!(
                output,
                "- **{}** when {}: {}",
                export::safe_text(&variation.name),
                export::safe_text(&variation.when),
                export::safe_text(&variation.difference)
            );
            export::confidence(&mut output, "  Evidence", &variation.confidence);
        }
        output.push('\n');
    }

    export::render_artifact_list(
        &mut output,
        "Outputs",
        &workflow.outputs,
        "No outputs were captured; completion criteria remain unspecified.",
    );
    export::heading(&mut output, 2, "Source trace");
    export::render_provenance(
        &mut output,
        &workflow.provenance,
        "No provenance was captured for this document.",
    );
    output
}
