# Problem Statement: Automating Sablon Template Generation from Descriptive Word Documents

## 1. Background
The current system utilizes the `Sablon` gem to generate documents (e.g., Capital Commitment agreements) by merging data from a Ruby context into a pre-defined `.docx` template.

As seen in [`app/packs/funds/capital_commitments/services/capital_commitment_doc_generator.rb`](app/packs/funds/capital_commitments/services/capital_commitment_doc_generator.rb), the generation process follows this flow:
1.  **Template Loading:** `template = Sablon.template(...)`
2.  **Context Preparation:** A Hash is created containing objects like `entity`, `fund`, `capital_commitment`, `investor_kyc`, etc., often wrapped in `TemplateDecorator`.
3.  **Merging:** `convert(template, context, file_name)` which effectively calls `template.render(context)`.

## 2. The Problem
Creating Sablon templates manually is difficult and error-prone for non-technical users. Sablon requires specific "Mail Merge" fields or `{{field}}` syntax inside Word documents to identify where data should be inserted.

Users prefer to provide a "Descriptive Document" where placeholders are written in plain text, for example:
> "This agreement is entered into on **[date]** by **[entity.name]** regarding the **[fund.name]**."

Currently, a human must manually open Microsoft Word, find these `[...]` markers, and replace them with the correct Sablon-compatible merge fields that match the keys in the Ruby `context` (e.g., `{{date}}`, `{{entity.name}}`, etc.).

## 3. Goals
The objective is to automate the transformation of a **Descriptive Word Doc** into a **Sablon Template Doc**.

### Requirements:
1.  **Source Input:** A `.docx` file containing descriptive text markers in brackets, e.g., `[capital_commitment.amount]`.
2.  **Mapping Intelligence:** The system must recognize these markers and map them to the corresponding keys available in the `context` defined in the generator.
3.  **Output Template:** A valid `.docx` file where all `[...]` markers are replaced with Sablon-compatible merge fields or expressions.
4.  **Reusability:** The generated template must be compatible with the existing `CapitalCommitmentDocGenerator` (or similar services) to produce the final document when provided with the actual data context.

## 4. Proposed Workflow
1.  **Context Extraction:** Identify all available keys and nested attributes in the `context` (defined in `CapitalCommitmentDocGenerator`).
2.  **AI-Powered Mapping (using RubyLLM):**
    *   Extract the descriptive placeholders from the Word document (e.g., `[Name of the Investor]`).
    *   Use the `RubyLLM` gem to provide an AI model with:
        *   The list of available keys in the Sablon context.
        *   The descriptive markers found in the document.
    *   The AI will return a mapping between the human-readable description and the precise Sablon key (e.g., `[Name of the Investor]` -> `capital_commitment.investor_name`).
3.  **Template Transformation:**
    *   Read the Descriptive Word Doc.
    *   Replace the identified text patterns with Sablon-compatible merge fields using the AI-generated mapping.
4.  **Verification Phase:** Ensure the resulting document is a valid Sablon template that correctly renders when passed a test context.

## 5. AI Prompt Strategy (Mapping Intelligence)
To ensure high accuracy in mapping, the `RubyLLM` prompt should include:
- **Context Schema:** A structured representation of the available data (e.g., `capital_commitment`, `fund`, `entity`, `investor_kyc`).
- **Sample Data:** Examples of the values these keys hold to help the AI understand the semantic meaning.
- **Instruction:** "Given a descriptive placeholder found in a legal document, identify the most appropriate key from the provided context schema to replace it with."

## 6. Implementation Details

### Component A: Context Schema Builder
A utility that reflects on the `context` Hash provided to Sablon. It will:
- Traverse the Hash and identify the classes of objects (e.g., `CapitalCommitment`, `Fund`).
- Use the `TemplateDecorator` (if available) or the model's attribute list to build a tree of available fields.
- Export this as a JSON/text schema for the LLM.

### Component B: Template Transformer
The main service that orchestrates the conversion:
1. **Placeholder Extraction:** Uses a docx-parsing library (like `docx` gem) to find all occurrences of `[...]`.
2. **AI Mapping:** Sends the extracted list and the Schema to `RubyLLM`.
3. **Template Re-writing:** Replaces the text nodes in the docx XML with Sablon Merge Fields (`{{...}}`).

### Component C: Sablon Generator Integration
Once the template is transformed, it is saved back to the system (e.g., as a `FundDocTemplate`) so that `CapitalCommitmentDocGenerator` can pick it up for standard generation.

## 7. Implementation Roadmap & Code Outlines

We have established two primary services to handle this logic:

1. **[`ContextSchemaBuilder`](app/packs/funds/capital_commitments/services/context_schema_builder.rb)**:
   - **Responsibility**: Inspects the Ruby context and creates a "Dictionary of available fields" for the AI.
   - **Key Feature**: Reflects on `ActiveRecord` models and `TemplateDecorator` instances to find valid paths (e.g. `fund.name`).

2. **[`TemplateTransformer`](app/packs/funds/capital_commitments/services/template_transformer.rb)**:
   - **Responsibility**: Orchestrates the document conversion.
   - **AI Integration**: Uses `RubyLLM` to map human text like `[Total Commitment]` to context keys like `capital_commitment.amount`.
   - **Document Generation**: Produces a `.docx` where the human text is replaced with Sablon expressions `{{...}}`.

### Technical TODOs in the Code:
- [ ] Implement recursive Hash/Object traversal in `ContextSchemaBuilder`.
- [ ] Implement `docx` XML parsing for placeholder extraction in `TemplateTransformer`.
- [ ] Define the `RubyLLM` prompt structure for high-precision mapping.
- [ ] Handle image placeholders (e.g., `[Signature]`) by mapping them to Sablon's image insertion syntax.

## 5. Constraints
- Do not modify the existing `CapitalCommitmentDocGenerator` logic for final document generation.
- The solution should focus specifically on the "Template-to-Template" conversion (Descriptive -> Sablon).
- Support for images (e.g., signatures) handled via `add_image` in the context should also be considered.
