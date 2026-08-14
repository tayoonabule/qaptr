//! Team-handoff-oriented Markdown rendering.

use std::fmt::Write as _;

use crate::{document::WorkflowDocument, export};

/// Renders a Workflow so another team can understand and take it over.
pub fn render(workflow: &WorkflowDocument) -> String {
    let mut output = String::new();
    export::heading(
        &mut output,
        1,
        &format!("Team Handoff: {}", export::safe_text(&workflow.title)),
    );
    output.push_str(
        "This handoff records what Qaptr observed. It separates evidence from gaps so the receiving team can validate the process before relying on it.\n\n",
    );

    export::heading(&mut output, 2, "Why this work exists");
    export::bullet(
        &mut output,
        "Goal",
        workflow
            .goal
            .as_deref()
            .unwrap_or("The goal was not captured"),
    );
    export::bullet(
        &mut output,
        "Working context",
        workflow
            .context
            .as_deref()
            .unwrap_or("The working context was not captured"),
    );
    export::confidence(&mut output, "Overall evidence", &workflow.confidence);
    output.push('\n');

    export::heading(&mut output, 2, "People and tools to align");
    if workflow.tools.is_empty() {
        output.push_str("No tools were captured. The receiving team should identify them rather than assume a stack.\n\n");
    } else {
        for tool in &workflow.tools {
            let _ = writeln!(
                output,
                "- **{}** — {}",
                export::safe_text(&tool.name),
                export::safe_text(tool.purpose.as_deref().unwrap_or("Role not captured"))
            );
            if let Some(usage) = &tool.observed_usage {
                export::bullet(&mut output, "  Observed handoff note", usage);
            }
            export::confidence(&mut output, "  Evidence", &tool.confidence);
        }
        output.push('\n');
    }

    export::render_artifact_list(
        &mut output,
        "Inputs the next person needs",
        &workflow.inputs,
        "No inputs were captured. The receiving team must establish prerequisites explicitly.",
    );
    export::render_artifact_list(
        &mut output,
        "Outputs to pass forward",
        &workflow.outputs,
        "No outputs were captured. The handoff has no observed completion artifact.",
    );

    export::heading(&mut output, 2, "Observed sequence");
    if workflow.steps.is_empty() {
        output.push_str(
            "No sequence was captured. There is nothing responsible to hand off as a step-by-step procedure.\n\n",
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
            if let Some(rationale) = &step.rationale {
                export::bullet(&mut output, "Intent", rationale);
            }
            if !step.tools.is_empty() {
                export::bullet(&mut output, "Tools to coordinate", &step.tools.join(", "));
            }
            if !step.inputs.is_empty() {
                export::bullet(&mut output, "Inputs", &step.inputs.join(", "));
            }
            if !step.outputs.is_empty() {
                export::bullet(&mut output, "Outputs", &step.outputs.join(", "));
            }
            export::confidence(&mut output, "Evidence", &step.confidence);
            output.push('\n');
        }
    }

    export::heading(&mut output, 2, "Decisions and open questions");
    if workflow.decision_points.is_empty() {
        output.push_str("No decision points were captured. This does not establish that the work has no branches.\n\n");
    } else {
        for decision in &workflow.decision_points {
            let _ = writeln!(output, "- **{}**", export::safe_text(&decision.question));
            export::bullet(
                &mut output,
                "Observed answer",
                decision
                    .observed_answer
                    .as_deref()
                    .unwrap_or("Not captured; confirm with the owner"),
            );
            for alternative in &decision.alternatives {
                let _ = writeln!(
                    output,
                    "  - Alternative: if {} → {}",
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
        output.push_str("No variations were captured. Ask the current owner about exceptions before standardizing.\n\n");
    } else {
        for variation in &workflow.variations {
            let _ = writeln!(
                output,
                "- **{}** — when {}: {}",
                export::safe_text(&variation.name),
                export::safe_text(&variation.when),
                export::safe_text(&variation.difference)
            );
            export::confidence(&mut output, "  Evidence", &variation.confidence);
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "Evidence trail");
    export::render_provenance(
        &mut output,
        &workflow.provenance,
        "No document-level provenance was captured.",
    );
    output
}
