//! Onboarding-oriented Markdown rendering.

use std::fmt::Write as _;

use crate::{document::WorkflowDocument, export};

/// Renders a Workflow as a guided learning document for a new practitioner.
pub fn render(workflow: &WorkflowDocument) -> String {
    let mut output = String::new();
    export::heading(
        &mut output,
        1,
        &format!("Onboarding Guide: {}", export::safe_text(&workflow.title)),
    );
    output.push_str(
        "Use this guide to learn the observed path. Items marked with low or unknown confidence require confirmation from an experienced owner.\n\n",
    );

    export::heading(&mut output, 2, "What you will learn");
    export::bullet(
        &mut output,
        "Goal",
        workflow
            .goal
            .as_deref()
            .unwrap_or("The intended goal was not captured"),
    );
    export::bullet(
        &mut output,
        "Context",
        workflow
            .context
            .as_deref()
            .unwrap_or("The context was not captured"),
    );
    export::confidence(&mut output, "Evidence status", &workflow.confidence);
    output.push('\n');

    export::heading(&mut output, 2, "Before you begin");
    if workflow.inputs.is_empty() {
        output.push_str(
            "No prerequisites were captured. Ask an owner what must be ready before starting.\n\n",
        );
    } else {
        for input in &workflow.inputs {
            let requirement = if input.required {
                "Required"
            } else {
                "Optional"
            };
            let description = input
                .description
                .as_deref()
                .unwrap_or("No explanation was captured");
            let _ = writeln!(
                output,
                "- **{requirement}:** {} — {}",
                export::safe_text(&input.name),
                export::safe_text(description)
            );
            export::confidence(&mut output, "  Evidence", &input.confidence);
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "Tools and vocabulary");
    if workflow.tools.is_empty() {
        output.push_str("No tools were captured. This guide does not guess which applications you should use.\n\n");
    } else {
        for tool in &workflow.tools {
            let purpose = tool.purpose.as_deref().unwrap_or("Purpose not captured");
            let _ = writeln!(
                output,
                "- **{}:** {}",
                export::safe_text(&tool.name),
                export::safe_text(purpose)
            );
            if let Some(usage) = &tool.observed_usage {
                export::bullet(&mut output, "  What was observed", usage);
            }
            export::confidence(&mut output, "  Evidence", &tool.confidence);
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "Guided walkthrough");
    if workflow.steps.is_empty() {
        output.push_str(
            "No walkthrough steps were captured. A learner should not be asked to fill in the missing procedure from this document.\n\n",
        );
    } else {
        for (index, step) in workflow.steps.iter().enumerate() {
            let _ = writeln!(
                output,
                "### Lesson {}: {}\n",
                index + 1,
                export::safe_text(&step.name)
            );
            export::bullet(&mut output, "Do", &step.action);
            export::bullet(
                &mut output,
                "Why",
                step.rationale
                    .as_deref()
                    .unwrap_or("The reason was not captured"),
            );
            if !step.tools.is_empty() {
                export::bullet(&mut output, "Use", &step.tools.join(", "));
            }
            if !step.inputs.is_empty() {
                export::bullet(&mut output, "Start with", &step.inputs.join(", "));
            }
            if !step.outputs.is_empty() {
                export::bullet(&mut output, "Look for", &step.outputs.join(", "));
            }
            export::confidence(&mut output, "Evidence", &step.confidence);
            output.push('\n');
        }
    }

    export::heading(&mut output, 2, "When the path changes");
    if workflow.decision_points.is_empty() && workflow.variations.is_empty() {
        output.push_str("No branches or variations were captured. Ask before improvising when the situation differs.\n\n");
    } else {
        for decision in &workflow.decision_points {
            let _ = writeln!(
                output,
                "- **Ask:** {}",
                export::safe_text(&decision.question)
            );
            export::bullet(
                &mut output,
                "Observed answer",
                decision
                    .observed_answer
                    .as_deref()
                    .unwrap_or("Not captured"),
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
        for variation in &workflow.variations {
            let _ = writeln!(
                output,
                "- **Variation: {}** — when {}: {}",
                export::safe_text(&variation.name),
                export::safe_text(&variation.when),
                export::safe_text(&variation.difference)
            );
            export::confidence(&mut output, "  Evidence", &variation.confidence);
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "You are done when");
    if workflow.outputs.is_empty() {
        output.push_str(
            "No completion outputs were captured. Ask the owner how to verify success.\n\n",
        );
    } else {
        for output_artifact in &workflow.outputs {
            let _ = writeln!(
                output,
                "- {}{}",
                if output_artifact.required {
                    "[ ] "
                } else {
                    "[ ] (optional) "
                },
                export::safe_text(&output_artifact.name)
            );
            if let Some(description) = &output_artifact.description {
                export::bullet(&mut output, "  Check", description);
            }
            export::confidence(&mut output, "  Evidence", &output_artifact.confidence);
        }
        output.push('\n');
    }

    export::heading(&mut output, 2, "Source note");
    export::render_provenance(
        &mut output,
        &workflow.provenance,
        "No provenance was captured. Treat this guide as incomplete until an owner confirms it.",
    );
    output
}
