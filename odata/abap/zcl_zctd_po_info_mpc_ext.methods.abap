METHOD define.
* Entity media POJson: MimeType là thuộc tính content type (bắt buộc với media entity)
    super->define( ).
    model->get_entity_type( 'POJson' )->get_property( 'MimeType' )->set_as_content_type( ).
ENDMETHOD.
