const SchemaFieldSet = @import("main.zig").SchemaFieldSet;
pub const admin = struct {
    pub const read = SchemaFieldSet.initEmpty();
    pub const update = SchemaFieldSet.initEmpty();
};
pub const customer = struct {
    pub const read = SchemaFieldSet.initEmpty();
    pub const update = SchemaFieldSet.initEmpty();
};
pub const public = struct {
    pub const read = SchemaFieldSet.initFull();
    pub const update = SchemaFieldSet.initOne(.xa_id);
};
