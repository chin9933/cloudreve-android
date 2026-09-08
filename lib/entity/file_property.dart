class Property {
  late String createdAt;
  late String updatedAt;
  late String policy;
  late int size;
  late int childFolderNum;
  late int childFileNum;
  late String path;
  late String queryDate;

  Property(
    this.createdAt,
    this.updatedAt,
    this.policy,
    this.size,
    this.childFolderNum,
    this.childFileNum,
    this.path,
    this.queryDate,
  );

  Property.fromJson(Map<String, dynamic> json) {
    createdAt = json['created_at'];
    updatedAt = json['updated_at'];
    policy = json['policy'];
    size = json['size'];
    childFolderNum = json['child_folder_num'];
    childFileNum = json['child_file_num'];
    path = json['path'];
    queryDate = json['query_date'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['created_at'] = createdAt;
    data['updated_at'] = updatedAt;
    data['policy'] = policy;
    data['size'] = size;
    data['child_folder_num'] = childFolderNum;
    data['child_file_num'] = childFileNum;
    data['path'] = path;
    data['query_date'] = queryDate;
    return data;
  }
}
