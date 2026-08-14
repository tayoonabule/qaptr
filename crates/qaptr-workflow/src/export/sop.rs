//! Standard-operating-procedure Markdown rendering.

use std::fmt::Write as _;

use crate::{document::WorkflowDocument, export};

/// Renders a Workflow as a formal, reviewable standard operating procedure.
pub fn render(workflow: &WorkflowDocument) -> String {
    let mut output = String::new();
    export::heading(
        &mut output,
        1,
        &format!(
            "Standard Operating Procedure: {}",
            export::safe_text(&workflow.title)
        ),
    );
    output.push_str(
        "This SOP is a record of observed work, not a guarantee that unobserved cases are covered. Review low-confidence and unknown material before adopting it as a standard.\n\n",
    );

    export::heading(&mut output, 2, "Purpose and scope");
    export::bullet(
        &mut output,
        "Purpose",
        workflow.goal.as_deref().unwrap_or("Purpose not captured"),
    );
    export::bullet(
        &mut output,
        "Scope",
        workflow
            .context
            .as_deref()
            .unwrap_or("Scope and operating context not captured"),
    );
    export::confidence(&mut output, "Evidence confidence", &workflow.confidence);
    output.push('\n');

    export::render_artifact_list(
        &mut output,
        "Required resources",
        &workflow.inputs,
        "No required resources were captured. The SOP cannot establish prerequisites.",
    );

    export::heading(&mut output, 2, "Observed tools");
    if workflow.tools.is_empty() {
        output.push_str(
            "No tools were captured. Do not add a tool to this SOP without separate evidence.\n\n",
        );
    } else {
        let _ = writeln!(
            output,
            "| Tool | Observed role | Confidence |\n|---|---|---|"
        );
        for tool in &workflow.tools {
            let role = tool.purpose.as_deref().unwrap_or("Role not captured");
            let _ = writeln!(
                output,
                "| {} | {} | {} |",
                export::safe_text(&tool.name),
                export::safe_text(role),
                export::confidence_text(&tool.confidence)
            );
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "Procedure");
    if workflow.steps.is_empty() {
        output.push_str(
            "No procedure steps were captured. This SOP is intentionally incomplete and must not be completed by inference.\n\n",
        );
    } else {
        for (index, step) in workflow.steps.iter().enumerate() {
            let _ = writeln!(
                output,
                "### {}. {}\n",
                index + 1,
                export::safe_text(&step.name)
            );
            export::bullet(&mut output, "Action", &step.action);
            export::bullet(
                &mut output,
                "Purpose",
                step.rationale.as_deref().unwrap_or("Purpose not captured"),
            );
            if !step.tools.is_empty() {
                export::bullet(&mut output, "Tools", &step.tools.join(", "));
            }
            if !step.inputs.is_empty() {
                export::bullet(&mut output, "Inputs", &step.inputs.join(", "));
            }
            if !step.outputs.is_empty() {
                export::bullet(&mut output, "Expected result", &step.outputs.join(", "));
            }
            export::confidence(&mut output, "Evidence", &step.confidence);
            output.push('\n');
        }
    }

    export::heading(&mut output, 2, "Decision table");
    if workflow.decision_points.is_empty() {
        output.push_str("No decision points were captured. No branch coverage is claimed.\n\n");
    } else {
        let _ = writeln!(
            output,
            "| Condition observed | Observed path | Confidence |\n|---|---|---|"
        );
        for decision in &workflow.decision_points {
            let answer = decision
                .observed_answer
                .as_deref()
                .unwrap_or("Path not captured");
            let _ = writeln!(
                output,
                "| {} | {} | {} |",
                export::safe_text(&decision.question),
                export::safe_text(answer),
                export::confidence_text(&decision.confidence)
            );
            for alternative in &decision.alternatives {
                let _ = writeln!(
                    output,
                    "| If {} | {} | alternative recorded |",
                    export::safe_text(&alternative.condition),
                    export::safe_text(&alternative.outcome)
                );
            }
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "Exceptions and variations");
    if workflow.variations.is_empty() {
        output.push_str("No variations were captured. Exception coverage is unknown.\n\n");
    } else {
        for variation in &workflow.variations {
            let _ = writeln!(
                output,
                "- **{}** applies when {}. Difference: {}",
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
        "Expected outputs",
        &workflow.outputs,
        "No outputs were captured. The SOP has no observed completion record.",
    );
    export::heading(&mut output, 2, "Records and provenance");
    export::render_provenance(
        &mut output,
        &workflow.provenance,
        "No provenance was captured for this SOP.",
    );
    output
}
