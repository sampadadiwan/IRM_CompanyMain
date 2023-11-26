module CocoonHelper
  def link_to_add_fields(name, form, type, associations)
    new_object = form.object.send "build_#{type}"
    id = "new_#{type}"
    fields = form.send("#{type}_fields", new_object, child_index: id) do |builder|
      render("/layouts/#{type}_fields", f: builder, associations:)
    end
    link_to(name, '#', class: "add_fields btn btn-outline-success", 'data-bs-toggle': "tooltip", 'data-bs-placement': "top", title: "Add Field", data: { id:, fields: fields.delete("\n") })
  end
end
